import type { AlmService } from './almService'
import type {
  DependencyRef,
  DiffModel,
  EnvironmentRef,
  ItemOutcome,
  Plan,
  PlanBlocker,
  PlanDependency,
  PlanOperation,
  RecordDiff,
  Run,
  RunItem,
  RunListItem,
  SelectionItem,
  StageResult,
  TableDiff,
} from '../types/alm'

// Sample data for running the app with no backend (VITE_ALM_SOURCE=mock): a Dev -> Test compare
// with a new mortgage-advice workstream and everything under it, changed settings, a duplicate, a
// channel that cannot be created by data, and manual steps. The plan and run below follow the same
// rules as the engine (backend/function-app/Modules/CcAlm), so every screen state can be seen.

const ENVIRONMENTS: EnvironmentRef[] = [
  { id: 'dev', name: 'Dev', url: 'https://contoso-dev.crm4.dynamics.com', role: 'any' },
  { id: 'test', name: 'Test', url: 'https://contoso-test.crm4.dynamics.com', role: 'any' },
  { id: 'acc', name: 'Acceptance', url: 'https://contoso-acc.crm4.dynamics.com', role: 'any' },
  { id: 'prod', name: 'Production', url: 'https://contoso-prod.crm4.dynamics.com', role: 'target', requireApproval: true },
]

interface TableDef {
  table: string
  label: string
  item: string
  group: string
  stage: number
  order: number
  /** Created only when missing, never updated. */
  createOnce?: boolean
  /** A create needs a per-environment record (a phone number). */
  external?: string
}

const TABLES: TableDef[] = [
  { table: 'msdyn_operatinghour', label: 'Operating hours', item: 'operating hours record', group: 'Foundations', stage: 1, order: 1 },
  { table: 'characteristic', label: 'Skills', item: 'skill', group: 'Foundations', stage: 1, order: 2 },
  { table: 'msdyn_capacityprofile', label: 'Capacity profiles', item: 'capacity profile', group: 'Foundations', stage: 1, order: 5 },
  { table: 'msdyn_sessiontemplate', label: 'Session templates', item: 'session template', group: 'Foundations', stage: 1, order: 7 },
  { table: 'msdyn_liveworkstream', label: 'Workstreams', item: 'workstream', group: 'Workstreams', stage: 2, order: 8 },
  { table: 'msdyn_ocliveworkstreamcontextvariable', label: 'Context variables', item: 'context variable', group: 'Workstreams', stage: 3, order: 10 },
  { table: 'queue', label: 'Queues', item: 'queue', group: 'Queues', stage: 4, order: 11 },
  { table: 'msdyn_decisioncontract', label: 'Decision contracts', item: 'decision contract', group: 'Routing', stage: 5, order: 12, createOnce: true },
  { table: 'msdyn_decisionruleset', label: 'Rulesets', item: 'ruleset', group: 'Routing', stage: 6, order: 13 },
  { table: 'msdyn_routingconfiguration', label: 'Routing configurations', item: 'routing configuration', group: 'Routing', stage: 7, order: 14 },
  { table: 'msdyn_routingconfigurationstep', label: 'Routing steps', item: 'routing step', group: 'Routing', stage: 7, order: 15 },
  { table: 'msdyn_ocvoicechannelsetting', label: 'Voice channels', item: 'voice channel', group: 'Channels', stage: 8, order: 19 },
  { table: 'msdyn_ocsmschannelsetting', label: 'SMS channels', item: 'SMS channel', group: 'Channels', stage: 8, order: 20, external: 'phone number' },
  { table: 'msdyn_cannedmessage', label: 'Quick replies', item: 'quick reply', group: 'Agent content', stage: 9, order: 22 },
]

const STAGES: Record<number, { label: string; description: string }> = {
  1: { label: 'Foundations', description: 'Operating hours, skills, rating models, capacity profiles and templates' },
  2: { label: 'Workstreams', description: 'The workstreams themselves' },
  3: { label: 'Workstream details', description: 'Capacity profiles per workstream and context variables' },
  4: { label: 'Queues', description: 'Unified routing queues' },
  5: { label: 'Decision contracts', description: 'Inputs and outputs that rulesets work on' },
  6: { label: 'Rulesets', description: 'Classification, route-to-queue and overflow rules' },
  7: { label: 'Routing and assignment', description: 'Routing configurations, assignment methods and their steps' },
  8: { label: 'Channels', description: 'Live chat, voice, SMS and WhatsApp settings' },
  9: { label: 'Agent content', description: 'Quick replies and tags' },
  10: { label: 'Contact center settings', description: 'The environment-wide Omnichannel configuration' },
  99: { label: 'Link records written earlier', description: 'Lookups that point at a table written later' },
}

const tableDef = (t: string) => TABLES.find((x) => x.table === t) as TableDef

interface MockRecord extends Omit<RecordDiff, 'dependsOn'> {
  table: string
  needs?: Array<{ key: string; via: string; deferred?: boolean }>
}

const WS = 'Mortgage advice voice'
const CFG = `${WS} › Contact center routing configuration`

// key format "table:name"; dependency targets refer to these keys.
const RECORDS: MockRecord[] = [
  { table: 'msdyn_operatinghour', matchKey: 'hours:nl', displayName: 'NL business hours', status: 'Equal', fields: [] },
  {
    table: 'msdyn_operatinghour', matchKey: 'hours:weekend', displayName: 'Weekend support', status: 'Changed',
    fields: [{ name: 'msdyn_timezone', label: 'Time zone', kind: 'value', source: '(GMT+01:00) Amsterdam, Berlin', target: '(GMT) Coordinated Universal Time' }],
  },
  { table: 'characteristic', matchKey: 'skill:dutch', displayName: 'Dutch', status: 'Equal', fields: [] },
  { table: 'characteristic', matchKey: 'skill:mortgages', displayName: 'Mortgages', status: 'MissingInTarget', fields: [] },
  { table: 'msdyn_capacityprofile', matchKey: 'cap:chat', displayName: 'Chat x3', status: 'Equal', fields: [] },
  {
    table: 'msdyn_capacityprofile', matchKey: 'cap:voice', displayName: 'Default voice', status: 'Ambiguous', fields: [],
    note: '2 records in the target share the same name, so they cannot be told apart. Rename or delete the extra one there.',
  },
  { table: 'msdyn_sessiontemplate', matchKey: 'session:mortgage', displayName: 'Mortgage case session', status: 'MissingInTarget', fields: [] },
  { table: 'msdyn_liveworkstream', matchKey: 'ws:sales', displayName: 'Sales chat', status: 'Equal', fields: [] },
  {
    table: 'msdyn_liveworkstream', matchKey: 'ws:mortgage', displayName: WS, status: 'MissingInTarget', fields: [],
    needs: [
      { key: 'msdyn_sessiontemplate|session:mortgage', via: 'default session template' },
      { key: 'msdyn_operatinghour|hours:weekend', via: 'Operating hours' },
      { key: 'queue|queue:mortgage', via: 'Default queue', deferred: true },
    ],
  },
  {
    table: 'msdyn_liveworkstream', matchKey: 'ws:billing', displayName: 'Billing chat', status: 'Changed',
    fields: [
      { name: 'msdyn_capacityrequired', label: 'Capacity required', kind: 'value', source: '5', target: '3' },
      { name: 'msdyn_workdistributionmode', label: 'Work distribution mode', kind: 'value', source: 'Push', target: 'Pick' },
      { name: 'msdyn_autocloseafterinactivity', label: 'Auto-close after inactivity', kind: 'value', source: '30 minutes', target: '1 day' },
    ],
    needs: [{ key: 'msdyn_operatinghour|hours:nl', via: 'Operating hours' }],
  },
  { table: 'msdyn_liveworkstream', matchKey: 'ws:legacy', displayName: 'Legacy email', status: 'ExtraInTarget', fields: [] },
  {
    table: 'msdyn_ocliveworkstreamcontextvariable', matchKey: 'cv:tier', displayName: 'Customer tier', context: WS, status: 'MissingInTarget', fields: [],
    needs: [{ key: 'msdyn_liveworkstream|ws:mortgage', via: 'Work stream' }],
  },
  { table: 'queue', matchKey: 'queue:sales', displayName: 'Sales', status: 'Equal', fields: [] },
  {
    table: 'queue', matchKey: 'queue:mortgage', displayName: 'Mortgage advice', status: 'MissingInTarget', fields: [],
    needs: [
      { key: 'msdyn_operatinghour|hours:weekend', via: 'Operating hours' },
      { key: 'msdyn_decisionruleset|rs:overflow', via: 'Pre-queue overflow ruleset', deferred: true },
    ],
  },
  {
    table: 'queue', matchKey: 'queue:escalations', displayName: 'Escalations', status: 'Changed',
    fields: [
      { name: 'msdyn_priority', label: 'Priority', kind: 'value', source: '1', target: '5' },
      { name: '_msdyn_operatinghourid_value', label: 'Operating hours', kind: 'lookup', source: "operating hours record 'Weekend support'", target: "operating hours record 'NL business hours'" },
    ],
    needs: [{ key: 'msdyn_operatinghour|hours:weekend', via: 'Operating hours' }],
  },
  { table: 'msdyn_decisioncontract', matchKey: 'dc:mortgage', displayName: 'Mortgage intake', status: 'MissingInTarget', fields: [] },
  {
    table: 'msdyn_decisionruleset', matchKey: 'rs:mortgage', displayName: 'Route mortgage calls', status: 'MissingInTarget', fields: [],
    needs: [
      { key: 'msdyn_decisioncontract|dc:mortgage', via: 'Input contract' },
      { key: 'queue|queue:mortgage', via: 'Rule set definition' },
      { key: 'characteristic|skill:mortgages', via: 'Rule set definition' },
    ],
  },
  { table: 'msdyn_decisionruleset', matchKey: 'rs:overflow', displayName: 'Mortgage overflow', status: 'MissingInTarget', fields: [], needs: [{ key: 'queue|queue:escalations', via: 'Rule set definition' }] },
  {
    table: 'msdyn_decisionruleset', matchKey: 'rs:sales', displayName: 'Route sales chats', status: 'Changed',
    fields: [{ name: 'msdyn_rulesetdefinition', label: 'Rule set definition', kind: 'definition', source: "now also uses queue 'Escalations'", target: null }],
    needs: [{ key: 'queue|queue:escalations', via: 'Rule set definition' }],
  },
  {
    table: 'msdyn_routingconfiguration', matchKey: 'rc:mortgage', displayName: 'Contact center routing configuration', context: WS, status: 'MissingInTarget', fields: [],
    needs: [{ key: 'msdyn_liveworkstream|ws:mortgage', via: 'Work stream' }],
  },
  {
    table: 'msdyn_routingconfiguration', matchKey: 'rc:billing', displayName: 'Contact center routing configuration', context: 'Billing chat', status: 'Equal', fields: [],
    needs: [{ key: 'msdyn_liveworkstream|ws:billing', via: 'Work stream' }],
  },
  {
    table: 'msdyn_routingconfigurationstep', matchKey: 'step:billing', displayName: 'Route to queue', context: 'Billing chat › Contact center routing configuration', status: 'Changed',
    fields: [{ name: '_msdyn_rulesetid_value', label: 'Rule set', kind: 'lookup', source: "ruleset 'Route sales chats'", target: "ruleset 'Route billing (old)'" }],
    needs: [
      { key: 'msdyn_routingconfiguration|rc:billing', via: 'Routing configuration' },
      { key: 'msdyn_decisionruleset|rs:sales', via: 'Rule set' },
    ],
  },
  {
    table: 'msdyn_routingconfigurationstep', matchKey: 'step:mortgage', displayName: 'Route to queue', context: CFG, status: 'MissingInTarget', fields: [],
    needs: [
      { key: 'msdyn_routingconfiguration|rc:mortgage', via: 'Routing configuration' },
      { key: 'msdyn_decisionruleset|rs:mortgage', via: 'Rule set' },
    ],
  },
  {
    table: 'msdyn_ocvoicechannelsetting', matchKey: 'voice:mortgage', displayName: 'Mortgage line', status: 'MissingInTarget', fields: [],
    needs: [{ key: 'msdyn_liveworkstream|ws:mortgage', via: 'Work stream' }],
  },
  {
    table: 'msdyn_ocsmschannelsetting', matchKey: 'sms:alerts', displayName: 'Appointment reminders', status: 'MissingInTarget', fields: [],
    needs: [{ key: 'msdyn_liveworkstream|ws:sales', via: 'Work stream' }],
  },
  {
    table: 'msdyn_cannedmessage', matchKey: 'qr:greeting', displayName: 'Greeting', context: 'English', status: 'Changed',
    fields: [{ name: 'msdyn_message', label: 'Message', kind: 'value', source: 'Hi {customer}, thanks for contacting Contoso. How can I help?', target: 'Hello, how can I help?' }],
  },
]

const refOf = (r: MockRecord) => `${r.table}|${r.matchKey}`
const byRef = new Map(RECORDS.map((r) => [refOf(r), r]))

function labelOf(ref: string): string {
  const r = byRef.get(ref)
  if (!r) return 'a record'
  const name = r.context ? `${r.context} › ${r.displayName}` : r.displayName
  return `${tableDef(r.table).item} '${name}'`
}

function dependsOf(r: MockRecord): DependencyRef[] {
  if (r.status === 'ExtraInTarget' || r.status === 'Ambiguous') return []
  return (r.needs ?? []).map((n) => {
    const [table, matchKey] = n.key.split('|')
    const kind = n.via === 'Rule set definition' ? 'embedded' : n.via.includes('template') ? 'name' : 'lookup'
    return { table, matchKey, label: labelOf(n.key), via: n.via, deferred: !!n.deferred, kind }
  })
}

function buildDiff(source: string, target: string): DiffModel {
  const tables: TableDiff[] = TABLES.map((t) => ({
    table: t.table,
    label: t.label,
    group: t.group,
    stage: t.stage,
    records: RECORDS.filter((r) => r.table === t.table).map((r) => ({
      matchKey: r.matchKey,
      status: r.status,
      displayName: r.displayName,
      context: r.context ?? null,
      note: r.note ?? null,
      fields: r.fields,
      dependsOn: dependsOf(r),
    })),
  }))
  const count = (s: string) => RECORDS.filter((r) => r.status === s).length
  return {
    diffId: `dif_${Math.random().toString(36).slice(2, 14)}`,
    source,
    target,
    generated: new Date().toISOString(),
    summary: {
      missingInTarget: count('MissingInTarget'),
      extraInTarget: count('ExtraInTarget'),
      changed: count('Changed'),
      equal: count('Equal'),
      ambiguous: count('Ambiguous'),
    },
    tables,
    detectOnly: [
      { type: 'phoneNumber', table: 'msdyn_ocvoicechannelsetting', label: 'Voice channels', record: 'Mortgage line', message: 'Uses a phone number. Acquire a number in the target environment and assign it to this channel.' },
      { type: 'voiceBot', table: 'msdyn_liveworkstream', label: 'Workstreams', record: WS, message: 'Uses a Copilot Studio agent. Move the agent by solution, then pick it on the workstream in the target.' },
    ],
    notices: [
      { severity: 'warning', table: 'msdyn_livechatconfig', message: 'The target has an older version of Live chat widgets: Enable message reaction does not exist there and will not be copied.' },
    ],
  }
}

/** The same rules as New-CcPlan in the engine. */
function buildPlan(diff: DiffModel, selection: SelectionItem[] | undefined, includeDependencies: boolean): Plan {
  const movable = (ref: string) => {
    const r = byRef.get(ref)
    return !!r && (r.status === 'MissingInTarget' || r.status === 'Changed')
  }
  const planned = new Map<string, 'selected' | 'dependency'>()
  const neededBy = new Map<string, string[]>()
  const ignored: Plan['ignored'] = []
  const start = selection ? selection.map((s) => `${s.table}|${s.matchKey}`) : RECORDS.map(refOf).filter(movable)
  for (const ref of start) {
    if (movable(ref)) planned.set(ref, 'selected')
    else if (byRef.get(ref)) {
      const r = byRef.get(ref) as MockRecord
      ignored.push({ table: r.table, matchKey: r.matchKey, displayName: r.displayName, reason: r.note ?? 'Not moved: it is already the same in the target.' })
    }
  }
  if (includeDependencies) {
    const queue = [...planned.keys()]
    while (queue.length) {
      const ref = queue.shift() as string
      for (const d of dependsOf(byRef.get(ref) as MockRecord)) {
        const dRef = `${d.table}|${d.matchKey}`
        if (byRef.get(dRef)?.status !== 'MissingInTarget') continue
        neededBy.set(dRef, [...(neededBy.get(dRef) ?? []), labelOf(ref)].filter((v, i, a) => a.indexOf(v) === i))
        if (!planned.has(dRef)) {
          planned.set(dRef, 'dependency')
          queue.push(dRef)
        }
      }
    }
  }

  const refs = [...planned.keys()].sort((a, b) => {
    const ra = byRef.get(a) as MockRecord
    const rb = byRef.get(b) as MockRecord
    return tableDef(ra.table).order - tableDef(rb.table).order || ra.displayName.localeCompare(rb.displayName)
  })
  const opByRef = new Map<string, PlanOperation>()
  const ops: PlanOperation[] = refs.map((ref, i) => {
    const r = byRef.get(ref) as MockRecord
    const t = tableDef(r.table)
    let op: PlanOperation['op'] = r.status === 'MissingInTarget' ? 'create' : 'update'
    if (t.createOnce && op === 'update') op = 'skip-existing'
    const o: PlanOperation = {
      seq: i + 1, stage: t.stage, table: r.table, tableLabel: t.label, op, matchKey: r.matchKey,
      displayName: r.displayName, context: r.context ?? null, status: 'ready',
      autoIncluded: planned.get(ref) === 'dependency', neededBy: neededBy.get(ref) ?? [],
      changes: r.fields.map((f) => f.label), dependencies: [], blockers: [], warnings: [],
    }
    opByRef.set(ref, o)
    return o
  })

  for (const o of ops) {
    const r = byRef.get(`${o.table}|${o.matchKey}`) as MockRecord
    const t = tableDef(o.table)
    if (o.op === 'create' && t.external) {
      o.blockers.push({ code: 'external', message: `Needs a ${t.external} to be created, and that is set up per environment. Set this channel up in the target, then compare again to copy its settings.`, fix: null })
    }
    for (const d of dependsOf(r)) {
      const dRef = `${d.table}|${d.matchKey}`
      const dep: PlanDependency = { table: d.table, matchKey: d.matchKey, label: d.label, via: d.via, state: 'inTarget' }
      const target = byRef.get(dRef)
      if (!target || target.status !== 'MissingInTarget') dep.state = 'inTarget'
      else if (opByRef.get(dRef)?.op === 'create') dep.state = d.deferred ? 'linkedLater' : 'createdEarlier'
      else {
        dep.state = 'missing'
        const blocker: PlanBlocker = {
          code: 'missingDependency',
          message: `Needs ${d.label}, which is not in the target and not selected.`,
          fix: { action: 'include', table: d.table, matchKey: d.matchKey, label: `Add ${d.label}` },
        }
        o.blockers.push(blocker)
      }
      o.dependencies.push(dep)
    }
    if (o.blockers.length) o.status = 'blocked'
  }
  let changed = true
  while (changed) {
    changed = false
    for (const o of ops) {
      if (o.status === 'blocked') continue
      const parent = o.dependencies
        .filter((d) => d.state === 'createdEarlier' || d.state === 'linkedLater')
        .map((d) => opByRef.get(`${d.table}|${d.matchKey}`))
        .find((p) => p?.status === 'blocked')
      if (parent) {
        o.blockers.push({ code: 'waitsOnBlocked', message: `Waits on ${labelOf(`${parent.table}|${parent.matchKey}`)}, which is blocked.`, fix: null })
        o.status = 'blocked'
        changed = true
      }
    }
  }

  const stageNumbers = [...new Set(ops.map((o) => o.stage))].sort((a, b) => a - b)
  return {
    planId: `pln_${Math.random().toString(36).slice(2, 14)}`,
    diffId: diff.diffId,
    source: diff.source,
    target: diff.target,
    created: new Date().toISOString(),
    summary: {
      total: ops.length,
      ready: ops.filter((o) => o.status === 'ready').length,
      blocked: ops.filter((o) => o.status === 'blocked').length,
      autoIncluded: ops.filter((o) => o.autoIncluded).length,
      creates: ops.filter((o) => o.op === 'create').length,
      updates: ops.filter((o) => o.op === 'update').length,
      links: ops.flatMap((o) => o.dependencies).filter((d) => d.state === 'linkedLater').length,
    },
    operations: ops,
    ignored,
    stages: stageNumbers.map((s) => ({ stage: s, label: STAGES[s].label, description: STAGES[s].description })),
  }
}

function delay<T>(value: T, ms = 500): Promise<T> {
  return new Promise((resolve) => setTimeout(() => resolve(value), ms))
}

export class MockAlmService implements AlmService {
  private runs = new Map<string, Run>()

  listEnvironments(): Promise<EnvironmentRef[]> {
    return delay(ENVIRONMENTS, 200)
  }

  compare(sourceId: string, targetId: string): Promise<DiffModel> {
    return delay(buildDiff(sourceId, targetId), 1200)
  }

  plan(diff: DiffModel, selection?: SelectionItem[], includeDependencies = true): Promise<Plan> {
    return delay(buildPlan(diff, selection, includeDependencies), 500)
  }

  /** Like the backend: returns at once with a queued run and fills it in over time. */
  async apply(plan: Plan, mode: 'dryRun' | 'apply', approved: boolean): Promise<Run> {
    const final = this.finalRun(plan, mode, approved)
    const items = final.stages.flatMap((st) => st.items.map((i) => ({ ...i, stage: st.stage })))
    const started: Run = {
      ...final,
      state: 'Queued',
      phase: 'queued',
      progress: { done: 0, total: items.length, current: 'Waiting to start' },
      summary: { created: 0, updated: 0, linked: 0, skipped: 0, blocked: 0, failed: 0 },
      stages: [],
      problems: [],
      finishedAt: undefined,
    }
    this.runs.set(started.runId, started)
    const step = (ms: number) => new Promise((r) => setTimeout(r, ms))
    void (async () => {
      const set = (patch: Partial<Run>) => this.runs.set(started.runId, { ...(this.runs.get(started.runId) as Run), ...patch })
      await step(400)
      set({ state: 'Running', phase: 'comparing', progress: { done: 0, total: items.length, current: 'Reading both environments' } })
      await step(1300)
      set({ phase: 'planning', progress: { done: 0, total: items.length, current: 'Checking the plan' } })
      await step(600)
      for (let n = 1; n <= items.length; n++) {
        const it = items[n - 1]
        set({
          phase: it.stage === 99 ? 'linking' : 'writing',
          progress: { done: n - 1, total: items.length, current: `${it.tableLabel}: ${it.context ? `${it.context} › ` : ''}${it.displayName}` },
        })
        await step(it.tableLabel === 'Workstreams' && it.op === 'create' && mode === 'apply' ? 1400 : 350)
        const doneItems = items.slice(0, n)
        const partial = this.withItems(final, doneItems)
        set({ stages: partial.stages, summary: partial.summary, problems: partial.problems, progress: { done: n, total: items.length, current: null } })
      }
      if (mode === 'apply') {
        set({ phase: 'verifying', progress: { done: items.length, total: items.length, current: 'Checking the target against the source' } })
        await step(1200)
      }
      set({ ...final, phase: 'done', progress: { done: items.length, total: items.length, current: null } })
    })()
    return delay(started, 250)
  }

  private withItems(final: Run, items: Array<RunItem & { stage: number }>): Run {
    const stages = final.stages
      .map((st) => ({ ...st, items: items.filter((i) => i.stage === st.stage) }))
      .filter((st) => st.items.length > 0)
    const count = (...o: ItemOutcome[]) => items.filter((i) => o.includes(i.outcome)).length
    return {
      ...final,
      stages,
      summary: {
        created: count('created', 'wouldCreate'), updated: count('updated', 'wouldUpdate'), linked: count('linked', 'wouldLink'),
        skipped: count('skipped'), blocked: count('blocked'), failed: count('failed'),
      },
      problems: items.filter((i) => ['blocked', 'skipped', 'failed'].includes(i.outcome)).map((i) => `${i.tableLabel} '${i.displayName}': ${i.message}`),
    }
  }

  private finalRun(plan: Plan, mode: 'dryRun' | 'apply', _approved: boolean): Run {
    const dry = mode === 'dryRun'
    const items: Array<RunItem & { stage: number }> = []
    for (const o of plan.operations) {
      let outcome: ItemOutcome
      let message: string
      if (o.status === 'blocked') {
        outcome = 'blocked'
        message = o.blockers.map((b) => b.message).join(' ')
      } else if (o.op === 'skip-existing') {
        outcome = 'unchanged'
        message = 'Already in the target; this table is never changed after it is created.'
      } else if (o.op === 'create') {
        outcome = dry ? 'wouldCreate' : 'created'
        message = dry ? `${12 + (o.seq % 9)} settings set.` : 'Done.'
      } else {
        outcome = dry ? 'wouldUpdate' : 'updated'
        message = dry ? `${o.changes.length || 1} setting${o.changes.length === 1 ? '' : 's'} written.` : 'Done.'
      }
      items.push({ seq: o.seq, stage: o.stage, table: o.table, tableLabel: o.tableLabel, displayName: o.displayName, context: o.context, op: o.op, outcome, message })
    }
    for (const o of plan.operations.filter((x) => x.status === 'ready')) {
      for (const d of o.dependencies.filter((x) => x.state === 'linkedLater')) {
        const verb = dry ? 'will point at' : 'now points at'
        items.push({
          seq: o.seq, stage: 99, table: o.table, tableLabel: o.tableLabel, displayName: o.displayName, context: o.context,
          op: 'link', outcome: dry ? 'wouldLink' : 'linked', message: `${d.via} of ${tableDef(o.table).item} '${o.displayName}' ${verb} ${d.label}.`,
        })
      }
    }
    const ok: ItemOutcome[] = ['created', 'updated', 'linked', 'unchanged', 'wouldCreate', 'wouldUpdate', 'wouldLink']
    const stages: StageResult[] = [...new Set(items.map((i) => i.stage))].sort((a, b) => a - b).map((stage) => {
      const si = items.filter((i) => i.stage === stage)
      const bad = si.filter((i) => !ok.includes(i.outcome))
      const good = si.filter((i) => ok.includes(i.outcome) && i.outcome !== 'unchanged')
      return {
        stage,
        label: STAGES[stage]?.label ?? `Stage ${stage}`,
        state: bad.length === 0 ? 'Succeeded' : good.length === 0 ? 'Failed' : 'PartiallyFailed',
        written: good.length,
        warnings: bad.map((i) => `${i.tableLabel} '${i.displayName}': ${i.message}`),
        items: si,
      }
    })
    const bad = items.filter((i) => !ok.includes(i.outcome))
    const count = (...o: ItemOutcome[]) => items.filter((i) => o.includes(i.outcome)).length
    const run: Run = {
      runId: `run_${Math.random().toString(36).slice(2, 14)}`,
      mode,
      source: plan.source,
      target: plan.target,
      state: bad.length === 0 ? 'Succeeded' : bad.length === items.length ? 'Failed' : 'PartiallyFailed',
      snapshotId: dry ? null : `snp_${Math.random().toString(36).slice(2, 10)}`,
      startedAt: new Date().toISOString(),
      finishedAt: new Date(Date.now() + 2400).toISOString(),
      summary: {
        created: count('created', 'wouldCreate'),
        updated: count('updated', 'wouldUpdate'),
        linked: count('linked', 'wouldLink'),
        skipped: count('skipped'),
        blocked: count('blocked'),
        failed: count('failed'),
      },
      stages,
      problems: bad.map((i) => `${i.tableLabel} '${i.displayName}': ${i.message}`),
    }
    if (!dry) {
      // Like the engine's check afterwards: every written record read back and compared again.
      const written = new Set(items.filter((i) => ['created', 'updated', 'linked'].includes(i.outcome)).map((i) => `${i.table}|${i.context ?? ''}|${i.displayName}`))
      const newWorkstreams = items.filter((i) => i.tableLabel === 'Workstreams' && i.outcome === 'created')
      run.verification = {
        state: 'Verified',
        checkedAt: new Date(Date.now() + 2400).toISOString(),
        checked: written.size,
        matched: written.size,
        differences: [],
        added: newWorkstreams.map((w) => ({
          table: 'msdyn_routingconfiguration',
          tableLabel: 'Routing configurations',
          displayName: `RC - Workstream: ${w.displayName}`,
          context: w.displayName,
        })),
      }
    }
    return run
  }

  listRuns(): Promise<RunListItem[]> {
    return delay(
      [...this.runs.values()].reverse().map((r) => ({
        runId: r.runId, mode: r.mode, source: r.source, target: r.target, state: r.state,
        startedAt: r.startedAt, finishedAt: r.finishedAt, summary: r.summary, snapshotId: r.snapshotId,
      })),
      150,
    )
  }

  getRun(runId: string): Promise<Run> {
    const run = this.runs.get(runId)
    if (!run) return Promise.reject(new Error(`Run ${runId} not found`))
    return delay(structuredClone(run), 120)
  }

  async rollback(runId: string): Promise<Run> {
    const run = this.runs.get(runId)
    if (!run) return Promise.reject(new Error(`Run ${runId} not found`))
    const rolling: Run = { ...run, state: 'RollingBack', phase: 'rollingBack', progress: { done: 0, total: 0, current: 'Restoring changed records and deleting created ones' } }
    this.runs.set(runId, rolling)
    setTimeout(() => {
      this.runs.set(runId, {
        ...run,
        state: 'RolledBack',
        phase: 'done',
        progress: { done: 0, total: 0, current: null },
        cleanup: { restored: run.summary.updated, deleted: run.summary.created, unresolved: [] },
      })
    }, 2200)
    return delay(rolling, 250)
  }
}
