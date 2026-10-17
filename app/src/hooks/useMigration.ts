import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { getAlmService } from '../services'
import { ACTIVE_RUN_STATES } from '../types/alm'
import type {
  DiffModel,
  EnvironmentRef,
  Plan,
  PlanFix,
  RecordDiff,
  Run,
  RunListItem,
  SelectionItem,
  TableDiff,
} from '../types/alm'

// The whole migration journey in one place: pick environments, review what differs, check the
// plan (preflight), dry-run, apply, roll back. Pages read from it and call its actions; nothing in
// a page talks to the service directly.

export type Step = 'environments' | 'review' | 'plan' | 'run'
export type Busy = null | 'environments' | 'compare' | 'plan' | 'dryRun' | 'apply' | 'rollback'

export const refOf = (table: string, matchKey: string) => `${table}|${matchKey}`
const splitRef = (ref: string): SelectionItem => {
  const i = ref.indexOf('|')
  return { table: ref.slice(0, i), matchKey: ref.slice(i + 1) }
}

export const isMovable = (r: RecordDiff) => r.status === 'MissingInTarget' || r.status === 'Changed'

const ACTIVE_RUN_KEY = 'ccalm.activeRun'
const POLL_MS = 1500
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms))
const remember = (runId: string | null) => {
  try {
    if (runId) localStorage.setItem(ACTIVE_RUN_KEY, runId)
    else localStorage.removeItem(ACTIVE_RUN_KEY)
  } catch {
    /* storage can be off; the run still finishes on the backend */
  }
}

export interface Migration {
  step: Step
  setStep: (s: Step) => void
  maxStep: Step
  environments: EnvironmentRef[]
  sourceId: string | null
  targetId: string | null
  source?: EnvironmentRef
  target?: EnvironmentRef
  setSource: (id: string) => void
  setTarget: (id: string) => void
  swap: () => void
  diff: DiffModel | null
  selected: Set<string>
  toggle: (ref: string) => void
  setMany: (refs: string[], on: boolean) => void
  includeDependencies: boolean
  setIncludeDependencies: (on: boolean) => void
  plan: Plan | null
  /** The dry run of the current plan, if one ran. */
  dryRun: Run | null
  run: Run | null
  runs: RunListItem[]
  busy: Busy
  error: string | null
  clearError: () => void
  compare: () => Promise<void>
  buildPlan: () => Promise<void>
  applyFix: (fix: PlanFix) => Promise<void>
  applyAllFixes: () => Promise<void>
  dropFromPlan: (refs: string[]) => Promise<void>
  execute: (mode: 'dryRun' | 'apply', approved: boolean) => Promise<void>
  rollback: () => Promise<void>
  startOver: () => void
  refreshRuns: () => Promise<void>
  /** Records by "table|key", for labels anywhere. */
  recordByRef: Map<string, { table: TableDiff; record: RecordDiff }>
  /** A record plus everything under it (its routing configurations, steps, context variables,
   *  channels) and what those use (rulesets, queues, templates), as movable refs. */
  bundleOf: (ref: string) => string[]
  /** Selects bundleOf(ref); returns how many records that added. */
  selectBundle: (ref: string) => number
}

const ORDER: Step[] = ['environments', 'review', 'plan', 'run']

export function useMigration(): Migration {
  const svc = getAlmService()
  const [environments, setEnvironments] = useState<EnvironmentRef[]>([])
  const [sourceId, setSourceId] = useState<string | null>(null)
  const [targetId, setTargetId] = useState<string | null>(null)
  const [step, setStepState] = useState<Step>('environments')
  const [diff, setDiff] = useState<DiffModel | null>(null)
  const [selected, setSelected] = useState<Set<string>>(new Set())
  const [includeDependencies, setIncludeDependenciesState] = useState(true)
  const [plan, setPlan] = useState<Plan | null>(null)
  const [dryRun, setDryRun] = useState<Run | null>(null)
  const [run, setRun] = useState<Run | null>(null)
  const [runs, setRuns] = useState<RunListItem[]>([])
  const [busy, setBusy] = useState<Busy>('environments')
  const [error, setError] = useState<string | null>(null)
  // Records the person added through a fix; kept so a re-plan does not drop them again.
  const extra = useRef<Set<string>>(new Set())
  // Records the person ticked themselves, as opposed to ones that came along with them.
  const ticked = useRef<Set<string>>(new Set())
  // Bumped to stop a poll loop that belongs to a run the person has moved away from.
  const watchToken = useRef(0)

  const refreshRuns = useCallback(async () => {
    if (!svc.listRuns) return
    try {
      setRuns(await svc.listRuns())
    } catch {
      /* history is a convenience; never block the flow on it */
    }
  }, [svc])

  useEffect(() => {
    svc
      .listEnvironments()
      .then((envs) => {
        setEnvironments(envs)
        // Sensible first pick: the first two environments, a target-only one never as source.
        const sources = envs.filter((e) => e.role !== 'target')
        if (sources[0]) setSourceId(sources[0].id)
        const t = envs.find((e) => e.id !== sources[0]?.id && e.role !== 'source')
        if (t) setTargetId(t.id)
      })
      .catch((e) => setError(e instanceof Error ? e.message : String(e)))
      .finally(() => setBusy(null))
    void refreshRuns()
  }, [svc, refreshRuns])

  const guard = useCallback(async (what: Busy, fn: () => Promise<void>) => {
    setBusy(what)
    setError(null)
    try {
      await fn()
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(null)
    }
  }, [])

  /** Polls a background run until it stops being active. Returns its final state. */
  const watch = useCallback(
    async (first: Run) => {
      const token = ++watchToken.current
      let r = first
      remember(r.runId)
      while (ACTIVE_RUN_STATES.includes(r.state)) {
        await sleep(POLL_MS)
        if (token !== watchToken.current) return r
        try {
          r = await svc.getRun(r.runId)
        } catch {
          continue // a missed poll (network blip) is retried on the next tick
        }
        if (token !== watchToken.current) return r
        setRun(r)
      }
      remember(null)
      return r
    },
    [svc],
  )

  // A run started before a reload, or in another tab, is picked up where it is.
  useEffect(() => {
    let runId: string | null = null
    try {
      runId = localStorage.getItem(ACTIVE_RUN_KEY)
    } catch {
      /* storage off */
    }
    if (!runId) return
    svc
      .getRun(runId)
      .then(async (r) => {
        if (!ACTIVE_RUN_STATES.includes(r.state)) {
          remember(null)
          return
        }
        setRun(r)
        setStepState('run')
        setBusy(r.state === 'RollingBack' ? 'rollback' : r.mode === 'apply' ? 'apply' : 'dryRun')
        try {
          const final = await watch(r)
          if (final.mode === 'dryRun') setDryRun(final)
        } finally {
          setBusy(null)
        }
      })
      .catch(() => remember(null))
  }, [svc, watch])

  const resetFrom = useCallback((s: Step) => {
    if (ORDER.indexOf(s) <= ORDER.indexOf('review')) {
      setDiff(null)
      ticked.current = new Set()
      setSelected(new Set())
      extra.current = new Set()
    }
    setPlan(null)
    setDryRun(null)
    setRun(null)
  }, [])

  const setSource = useCallback((id: string) => {
    setSourceId(id)
    resetFrom('review')
    setStepState('environments')
  }, [resetFrom])

  const setTarget = useCallback((id: string) => {
    setTargetId(id)
    resetFrom('review')
    setStepState('environments')
  }, [resetFrom])

  const swap = useCallback(() => {
    setSourceId(targetId)
    setTargetId(sourceId)
    resetFrom('review')
    setStepState('environments')
  }, [sourceId, targetId, resetFrom])

  const recordByRef = useMemo(() => {
    const m = new Map<string, { table: TableDiff; record: RecordDiff }>()
    for (const t of diff?.tables ?? []) for (const r of t.records) m.set(refOf(t.table, r.matchKey), { table: t, record: r })
    return m
  }, [diff])

  // Who sits under whom: a record points at its parent through a lookup to a table written before
  // it (a routing step to its routing configuration, that to its workstream). Lookups to a table
  // written later (a workstream's default queue) are references, not ownership, and are skipped.
  const childrenOf = useMemo(() => {
    const m = new Map<string, string[]>()
    for (const [ref, { record }] of recordByRef) {
      for (const d of record.dependsOn) {
        if (d.kind && d.kind !== 'lookup') continue
        if (d.deferred) continue
        const parent = refOf(d.table, d.matchKey)
        m.set(parent, [...(m.get(parent) ?? []), ref])
      }
    }
    return m
  }, [recordByRef])

  const bundleOf = useCallback(
    (start: string) => {
      const owned = new Set<string>([start])
      const queue = [start]
      while (queue.length) {
        for (const child of childrenOf.get(queue.shift() as string) ?? []) {
          if (!owned.has(child)) {
            owned.add(child)
            queue.push(child)
          }
        }
      }
      // Then everything those use that differs: the rulesets the steps run, the queues those
      // rulesets route to, the templates the workstream names.
      const all = new Set(owned)
      const next = [...owned]
      while (next.length) {
        const rec = recordByRef.get(next.shift() as string)?.record
        for (const d of rec?.dependsOn ?? []) {
          const ref = refOf(d.table, d.matchKey)
          const dep = recordByRef.get(ref)?.record
          if (!dep || all.has(ref) || !isMovable(dep)) continue
          all.add(ref)
          next.push(ref)
        }
      }
      return [...all].filter((r) => {
        const rec = recordByRef.get(r)?.record
        return !!rec && isMovable(rec)
      })
    },
    [childrenOf, recordByRef],
  )


  const compare = useCallback(
    () =>
      guard('compare', async () => {
        if (!sourceId || !targetId) throw new Error('Pick a source and a target first.')
        if (sourceId === targetId) throw new Error('Source and target must be different environments.')
        const d = await svc.compare(sourceId, targetId)
        setDiff(d)
        // Everything new or changed starts selected; the plan step shows exactly what that means.
        const all = d.tables.flatMap((t) => t.records.filter(isMovable).map((r) => refOf(t.table, r.matchKey)))
        ticked.current = new Set(all)
        setSelected(new Set(all))
        extra.current = new Set()
        setPlan(null)
        setDryRun(null)
        setRun(null)
        setStepState('review')
      }),
    [guard, sourceId, targetId, svc],
  )

  const planWith = useCallback(
    async (refs: Set<string>, include: boolean) => {
      if (!diff) throw new Error('Compare first.')
      const p = await svc.plan(diff, [...refs].map(splitRef), include)
      setPlan(p)
      setDryRun(null)
      setRun(null)
    },
    [diff, svc],
  )

  const buildPlan = useCallback(
    () =>
      guard('plan', async () => {
        const refs = new Set([...selected, ...extra.current])
        if (refs.size === 0) throw new Error('Select at least one record to move.')
        await planWith(refs, includeDependencies)
        setStepState('plan')
      }),
    [guard, selected, includeDependencies, planWith],
  )

  const setIncludeDependencies = useCallback(
    (on: boolean) => {
      setIncludeDependenciesState(on)
      if (plan) {
        void guard('plan', () => planWith(new Set([...selected, ...extra.current]), on))
      }
    },
    [plan, guard, planWith, selected],
  )

  const applyFix = useCallback(
    (fix: PlanFix) =>
      guard('plan', async () => {
        extra.current.add(refOf(fix.table, fix.matchKey))
        setSelected((s) => new Set([...s, refOf(fix.table, fix.matchKey)]))
        await planWith(new Set([...selected, ...extra.current, refOf(fix.table, fix.matchKey)]), includeDependencies)
      }),
    [guard, planWith, selected, includeDependencies],
  )

  const applyAllFixes = useCallback(
    () =>
      guard('plan', async () => {
        if (!plan || !diff) return
        // Follow the whole chain in one go: a record added as a fix can need records of its own.
        let current = plan
        const next = new Set([...selected, ...extra.current])
        for (let round = 0; round < 10; round++) {
          const fixes = current.operations.flatMap((o) => o.blockers.map((b) => b.fix).filter((f): f is PlanFix => !!f))
          const added = fixes.map((f) => refOf(f.table, f.matchKey)).filter((r) => !next.has(r))
          if (!added.length) break
          for (const r of added) {
            next.add(r)
            extra.current.add(r)
          }
          current = await svc.plan(diff, [...next].map(splitRef), includeDependencies)
        }
        setSelected(next)
        setPlan(current)
        setDryRun(null)
        setRun(null)
      }),
    [guard, plan, diff, svc, selected, includeDependencies],
  )

  const dropFromPlan = useCallback(
    (refs: string[]) =>
      guard('plan', async () => {
        const next = new Set(selected)
        for (const r of refs) {
          next.delete(r)
          extra.current.delete(r)
        }
        setSelected(next)
        if (next.size === 0) {
          setPlan(null)
          setStepState('review')
          return
        }
        await planWith(next, includeDependencies)
      }),
    [guard, selected, planWith, includeDependencies],
  )

  const execute = useCallback(
    (mode: 'dryRun' | 'apply', approved: boolean) =>
      guard(mode, async () => {
        if (!plan) throw new Error('Check the plan first.')
        const started = await svc.apply(plan, mode, approved)
        setRun(started)
        setStepState('run')
        void refreshRuns()
        const final = await watch(started)
        if (mode === 'dryRun') setDryRun(final)
        void refreshRuns()
      }),
    [guard, plan, svc, refreshRuns, watch],
  )

  const rollback = useCallback(
    () =>
      guard('rollback', async () => {
        if (!run) throw new Error('No run to roll back.')
        const started = await svc.rollback(run.runId)
        setRun(started)
        await watch(started)
        void refreshRuns()
      }),
    [guard, run, svc, refreshRuns, watch],
  )

  const startOver = useCallback(() => {
    watchToken.current++
    remember(null)
    resetFrom('review')
    setStepState('environments')
  }, [resetFrom])

  const maxStep: Step = run ? 'run' : plan ? 'plan' : diff ? 'review' : 'environments'
  const setStep = useCallback(
    (s: Step) => {
      if (ORDER.indexOf(s) <= ORDER.indexOf(maxStep)) setStepState(s)
    },
    [maxStep],
  )



  // Ticking a record ticks everything under it and what that uses (bundleOf): a workstream
  // brings its routing configuration, steps, rulesets and the rest. Unticking takes that away
  // again, except what another record that is still ticked needs.
  const setMany = useCallback(
    (refs: string[], on: boolean) => {
      setSelected((s) => {
        const n = new Set(s)
        if (on) {
          for (const r of refs) {
            ticked.current.add(r)
            for (const x of bundleOf(r)) n.add(x)
          }
          return n
        }
        const removed = new Set(refs.flatMap((r) => bundleOf(r)))
        for (const r of refs) removed.add(r)
        for (const x of removed) {
          n.delete(x)
          ticked.current.delete(x)
        }
        for (const t of ticked.current) {
          if (!n.has(t)) continue
          for (const x of bundleOf(t)) n.add(x)
        }
        return n
      })
    },
    [bundleOf],
  )

  const toggle = useCallback((ref: string) => setMany([ref], !selected.has(ref)), [setMany, selected])

  const selectBundle = useCallback(
    (ref: string) => {
      const added = bundleOf(ref).filter((r) => !selected.has(r)).length
      setMany([ref], true)
      return added
    },
    [bundleOf, selected, setMany],
  )

  return {
    step, setStep, maxStep, environments, sourceId, targetId,
    source: environments.find((e) => e.id === sourceId),
    target: environments.find((e) => e.id === targetId),
    setSource, setTarget, swap, diff, selected, toggle, setMany,
    includeDependencies, setIncludeDependencies, plan, dryRun, run, runs, busy, error,
    clearError: () => setError(null),
    compare, buildPlan, applyFix, applyAllFixes, dropFromPlan, execute, rollback, startOver, refreshRuns,
    recordByRef, bundleOf, selectBundle,
  }
}
