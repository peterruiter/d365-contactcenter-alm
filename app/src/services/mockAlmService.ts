import type { AlmService } from './almService'
import type {
  DiffModel,
  EnvironmentRef,
  Plan,
  PlanOperation,
  PlanStage,
  Run,
  SelectionItem,
  StageResult,
  TableDiff,
} from '../types/alm'

// Sample data grounded in real Contact Center config: workstreams, queues, routing
// rulesets, operating hours. Enough to exercise every UI state without a backend.

const ENVIRONMENTS: EnvironmentRef[] = [
  { id: 'dev', name: 'Dev', url: 'https://contoso-dev.crm4.dynamics.com', role: 'any' },
  { id: 'test', name: 'Test', url: 'https://contoso-test.crm4.dynamics.com', role: 'any' },
  { id: 'acc', name: 'Acceptance', url: 'https://contoso-acc.crm4.dynamics.com', role: 'any' },
  { id: 'prod', name: 'Production', url: 'https://contoso-prod.crm4.dynamics.com', role: 'target', requireApproval: true },
]

const TABLE_LABELS: Record<string, string> = {
  msdyn_operatinghour: 'Operating hours',
  msdyn_liveworkstream: 'Workstreams',
  queue: 'Queues',
  msdyn_decisioncontract: 'Decision contracts',
  msdyn_decisionruleset: 'Routing rulesets',
  msdyn_capacityprofile: 'Capacity profiles',
  msdyn_ocvoicechannelsetting: 'Voice channel',
}

function buildDiff(source: string, target: string): DiffModel {
  const tables: TableDiff[] = [
    {
      table: 'msdyn_operatinghour',
      label: TABLE_LABELS.msdyn_operatinghour,
      records: [
        { matchKey: 'NL business hours', status: 'Equal', fields: [], dependsOn: [] },
        {
          matchKey: 'Weekend support',
          status: 'Changed',
          fields: [{ name: 'msdyn_timezone', source: 'W. Europe', target: 'UTC' }],
          dependsOn: [],
        },
      ],
    },
    {
      table: 'msdyn_capacityprofile',
      label: TABLE_LABELS.msdyn_capacityprofile,
      records: [{ matchKey: 'Chat x3', status: 'Equal', fields: [], dependsOn: [] }],
    },
    {
      table: 'msdyn_liveworkstream',
      label: TABLE_LABELS.msdyn_liveworkstream,
      records: [
        { matchKey: 'Sales chat', status: 'Equal', fields: [], dependsOn: [] },
        {
          matchKey: 'Support voice',
          status: 'MissingInTarget',
          fields: [],
          // Depends on its operating hour, which is also not yet in sync in target.
          dependsOn: [{ table: 'msdyn_operatinghour', matchKey: 'Weekend support' }],
        },
        {
          matchKey: 'Billing chat',
          status: 'Changed',
          fields: [
            { name: 'msdyn_capacity', source: '5', target: '3' },
            { name: 'msdyn_notificationtemplateid', source: 'Chat incoming', target: 'Default' },
          ],
          dependsOn: [],
        },
        { matchKey: 'Old email queue', status: 'ExtraInTarget', fields: [], dependsOn: [] },
      ],
    },
    {
      table: 'queue',
      label: TABLE_LABELS.queue,
      records: [
        { matchKey: 'Sales queue', status: 'Equal', fields: [], dependsOn: [] },
        { matchKey: 'Support queue', status: 'MissingInTarget', fields: [], dependsOn: [] },
        // Auto-provisioned personal queues (one per user) are never a compare candidate - always
        // excluded, no override.
      ],
    },
    {
      table: 'msdyn_decisioncontract',
      label: TABLE_LABELS.msdyn_decisioncontract,
      records: [{ matchKey: 'new_incident_intentfamily', status: 'MissingInTarget', fields: [], dependsOn: [] }],
    },
    {
      table: 'msdyn_decisionruleset',
      label: TABLE_LABELS.msdyn_decisionruleset,
      records: [
        {
          matchKey: 'Sales routing',
          status: 'Changed',
          fields: [{ name: 'msdyn_rulesetdefinition', source: '<ruleset definition>', target: '<differs>' }],
          dependsOn: [],
        },
        {
          matchKey: 'Overflow rules',
          status: 'MissingInTarget',
          fields: [],
          // Depends on its decision contract, which does not exist in target either.
          dependsOn: [{ table: 'msdyn_decisioncontract', matchKey: 'new_incident_intentfamily' }],
        },
      ],
    },
  ]

  const all = tables.flatMap((t) => t.records)
  return {
    source,
    target,
    generated: new Date().toISOString(),
    summary: {
      missingInTarget: all.filter((r) => r.status === 'MissingInTarget').length,
      extraInTarget: all.filter((r) => r.status === 'ExtraInTarget').length,
      changed: all.filter((r) => r.status === 'Changed').length,
      equal: all.filter((r) => r.status === 'Equal').length,
    },
    tables,
    detectOnly: [
      {
        type: 'phoneNumber',
        table: 'msdyn_ocvoicechannelsetting',
        record: 'Support voice',
        message: 'Voice channel has an ACS phone number the target lacks. Re-acquire the number in the target.',
      },
      {
        type: 'voiceBot',
        table: 'msdyn_liveworkstream',
        record: 'Support voice',
        message: 'Workstream points at a Copilot Studio agent. Move the agent by solution, then rewire connection references.',
      },
    ],
  }
}

const STAGE_LABELS: Record<number, string> = {
  1: 'Foundations (hours, skills, capacity, templates)',
  2: 'Workstreams',
  3: 'Workstream joins and context variables',
  4: 'Queues',
  5: 'Decision contracts',
  6: 'Routing rulesets',
  7: 'Routing and assignment steps',
  8: 'Channel settings',
  9: 'Quick replies and tags',
  10: 'Omnichannel config',
}

const STAGE_FOR_TABLE: Record<string, number> = {
  msdyn_operatinghour: 1,
  msdyn_capacityprofile: 1,
  msdyn_liveworkstream: 2,
  queue: 4,
  msdyn_decisioncontract: 5,
  msdyn_decisionruleset: 6,
}

const ORDER_FOR_TABLE: Record<string, number> = {
  msdyn_operatinghour: 1,
  msdyn_capacityprofile: 5,
  msdyn_liveworkstream: 8,
  queue: 11,
  msdyn_decisioncontract: 12,
  msdyn_decisionruleset: 13,
}

function delay<T>(value: T, ms = 500): Promise<T> {
  return new Promise((resolve) => setTimeout(() => resolve(value), ms))
}

export class MockAlmService implements AlmService {
  private runs = new Map<string, Run>()

  listEnvironments(): Promise<EnvironmentRef[]> {
    return delay(ENVIRONMENTS, 200)
  }

  compare(sourceId: string, targetId: string, _tables?: string[]): Promise<DiffModel> {
    return delay(buildDiff(sourceId, targetId), 900)
  }

  plan(diff: DiffModel, selection?: SelectionItem[]): Promise<Plan> {
    const picked = selection
      ? new Set(selection.map((s) => `${s.table}|${s.matchKey}`))
      : null

    const ops: PlanOperation[] = []
    let seq = 0
    for (const t of diff.tables) {
      for (const r of t.records) {
        if (r.status !== 'MissingInTarget' && r.status !== 'Changed') continue
        if (picked && !picked.has(`${t.table}|${r.matchKey}`)) continue
        seq += 1
        ops.push({
          seq,
          stage: STAGE_FOR_TABLE[t.table] ?? 9,
          table: t.table,
          label: t.label,
          op: r.status === 'MissingInTarget' ? 'create' : 'update',
          matchKey: r.matchKey,
        })
      }
    }
    ops.sort((a, b) => (ORDER_FOR_TABLE[a.table] ?? 99) - (ORDER_FOR_TABLE[b.table] ?? 99) || a.seq - b.seq)
    ops.forEach((o, i) => (o.seq = i + 1))

    const stageNumbers = [...new Set([...Object.keys(STAGE_LABELS).map(Number), ...ops.map((o) => o.stage)])].sort(
      (a, b) => a - b,
    )
    const stages: PlanStage[] = stageNumbers.map((stage) => ({
      stage,
      label: STAGE_LABELS[stage] ?? `Stage ${stage}`,
      operations: ops.filter((o) => o.stage === stage),
    }))

    return delay({
      planId: `pln_${Math.random().toString(36).slice(2, 14)}`,
      source: diff.source,
      target: diff.target,
      created: new Date().toISOString(),
      operations: ops,
      stages,
    }, 400)
  }

  async apply(plan: Plan, mode: 'dryRun' | 'apply', _approved: boolean): Promise<Run> {
    const stages = [...new Set(plan.operations.map((o) => o.stage))].sort((a, b) => a - b)
    const stageResults: StageResult[] = stages.map((stage) => {
      const ops = plan.operations.filter((o) => o.stage === stage)
      const warnings: string[] = []
      if (stage === 2 && ops.some((o) => o.op === 'create')) {
        warnings.push('Provisioning confirmed for new workstreams after a short wait.')
      }
      return {
        stage,
        label: STAGE_LABELS[stage] ?? `Stage ${stage}`,
        state: 'Succeeded',
        written: ops.length,
        warnings,
      }
    })

    const run: Run = {
      runId: `run_${Math.random().toString(36).slice(2, 14)}`,
      mode,
      target: plan.target,
      state: mode === 'dryRun' ? 'Succeeded' : 'Succeeded',
      snapshotId: mode === 'apply' ? `snp_${Math.random().toString(36).slice(2, 10)}` : null,
      stages: stageResults,
      problems: [],
    }
    this.runs.set(run.runId, run)
    return delay(run, 700)
  }

  getRun(runId: string): Promise<Run> {
    const run = this.runs.get(runId)
    if (!run) return Promise.reject(new Error(`Run ${runId} not found`))
    return delay(run, 200)
  }

  async rollback(runId: string): Promise<Run> {
    const run = this.runs.get(runId)
    if (!run) return Promise.reject(new Error(`Run ${runId} not found`))
    const rolledBack: Run = { ...run, state: 'RolledBack' }
    this.runs.set(runId, rolledBack)
    return delay(rolledBack, 600)
  }
}
