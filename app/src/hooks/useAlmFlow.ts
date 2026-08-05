import { useCallback, useEffect, useState } from 'react'
import { getAlmService } from '../services'
import type {
  DiffModel,
  EnvironmentRef,
  Plan,
  Run,
  SelectionItem,
} from '../types/alm'

type Phase = 'idle' | 'comparing' | 'compared' | 'planning' | 'planned' | 'running' | 'done'

export interface AlmFlow {
  environments: EnvironmentRef[]
  sourceId: string | null
  targetId: string | null
  diff: DiffModel | null
  plan: Plan | null
  run: Run | null
  phase: Phase
  busy: boolean
  error: string | null
  setSource: (id: string) => void
  setTarget: (id: string) => void
  compare: () => Promise<void>
  buildPlan: (selection?: SelectionItem[]) => Promise<void>
  apply: (mode: 'dryRun' | 'apply', approved: boolean) => Promise<void>
  rollback: () => Promise<void>
  reset: () => void
}

export function useAlmFlow(): AlmFlow {
  const svc = getAlmService()
  const [environments, setEnvironments] = useState<EnvironmentRef[]>([])
  const [sourceId, setSourceId] = useState<string | null>(null)
  const [targetId, setTargetId] = useState<string | null>(null)
  const [diff, setDiff] = useState<DiffModel | null>(null)
  const [plan, setPlan] = useState<Plan | null>(null)
  const [run, setRun] = useState<Run | null>(null)
  const [phase, setPhase] = useState<Phase>('idle')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    svc.listEnvironments().then(setEnvironments).catch((e) => setError(String(e)))
  }, [svc])

  const guard = useCallback(async (fn: () => Promise<void>) => {
    setBusy(true)
    setError(null)
    try {
      await fn()
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }, [])

  const setSource = useCallback((id: string) => {
    setSourceId(id)
    setDiff(null)
    setPlan(null)
    setRun(null)
    setPhase('idle')
  }, [])

  const setTarget = useCallback((id: string) => {
    setTargetId(id)
    setDiff(null)
    setPlan(null)
    setRun(null)
    setPhase('idle')
  }, [])

  const compare = useCallback(
    () =>
      guard(async () => {
        if (!sourceId || !targetId) throw new Error('Pick a source and a target first.')
        if (sourceId === targetId) throw new Error('Source and target must differ.')
        setPhase('comparing')
        const result = await svc.compare(sourceId, targetId)
        setDiff(result)
        setPlan(null)
        setRun(null)
        setPhase('compared')
      }),
    [guard, sourceId, targetId, svc],
  )

  const buildPlan = useCallback(
    (selection?: SelectionItem[]) =>
      guard(async () => {
        if (!diff) throw new Error('Run a compare first.')
        setPhase('planning')
        const p = await svc.plan(diff, selection)
        setPlan(p)
        setRun(null)
        setPhase('planned')
      }),
    [diff, guard, svc],
  )

  const apply = useCallback(
    (mode: 'dryRun' | 'apply', approved: boolean) =>
      guard(async () => {
        if (!plan) throw new Error('Build a plan first.')
        setPhase('running')
        const r = await svc.apply(plan, mode, approved)
        setRun(r)
        setPhase('done')
      }),
    [guard, plan, svc],
  )

  const rollback = useCallback(
    () =>
      guard(async () => {
        if (!run) throw new Error('No run to roll back.')
        const r = await svc.rollback(run.runId)
        setRun(r)
      }),
    [guard, run, svc],
  )

  const reset = useCallback(() => {
    setDiff(null)
    setPlan(null)
    setRun(null)
    setPhase('idle')
    setError(null)
  }, [])

  return {
    environments, sourceId, targetId, diff, plan, run, phase, busy, error,
    setSource, setTarget, compare, buildPlan, apply, rollback, reset,
  }
}
