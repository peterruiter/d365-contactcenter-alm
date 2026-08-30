// Domain types for the Contact Center ALM app.
// These mirror the backend API contract in docs/architecture.md so the UI and the
// engine agree on shape. Keep them in sync when the contract changes.

export type EnvRole = 'any' | 'source' | 'target'

export interface EnvironmentRef {
  id: string
  name: string
  url: string
  role: EnvRole
  requireApproval?: boolean
}

export type RecordStatus = 'MissingInTarget' | 'ExtraInTarget' | 'Changed' | 'Equal'

export interface FieldDelta {
  name: string
  source: string | null
  target: string | null
}

export interface DependencyRef {
  table: string
  matchKey: string
}

export interface RecordDiff {
  matchKey: string
  status: RecordStatus
  fields: FieldDelta[]
  /** Other records this one points at (via manifest lookups). Selecting this record should also select any of these still missing or changed in the target. */
  dependsOn: DependencyRef[]
  /** Friendly name (e.g. msdyn_name) for tables matched on an opaque key like msdyn_uniquename. Absent when the match key is already readable - fall back to matchKey. */
  displayName?: string | null
}

export interface TableDiff {
  table: string
  /** Friendly label for the table, e.g. "Workstreams". */
  label: string
  records: RecordDiff[]
}

export interface DiffSummary {
  missingInTarget: number
  extraInTarget: number
  changed: number
  equal: number
}

export type DetectType = 'phoneNumber' | 'voiceBot' | 'channelAccount' | 'survey' | 'eventGrid'

export interface DetectFinding {
  type: DetectType
  table: string
  record: string
  message: string
}

export interface DiffModel {
  source: string
  target: string
  generated: string
  summary: DiffSummary
  tables: TableDiff[]
  detectOnly: DetectFinding[]
}

export type OpKind = 'create' | 'update' | 'skip-existing'

export interface PlanOperation {
  seq: number
  stage: number
  table: string
  label: string
  op: OpKind
  matchKey: string
  displayName?: string | null
}

export interface PlanStage {
  stage: number
  label: string
  operations: PlanOperation[]
}

export interface Plan {
  planId: string
  source: string
  target: string
  created: string
  operations: PlanOperation[]
  /** All canonical stages, in order, including ones with nothing to do - so the plan view can show the full pipeline rather than just the stages that happen to have work. */
  stages: PlanStage[]
}

export interface SelectionItem {
  table: string
  matchKey: string
}

export type RunState =
  | 'Queued'
  | 'Running'
  | 'Succeeded'
  | 'PartiallyFailed'
  | 'Failed'
  | 'RolledBack'

export type StageState = 'Pending' | 'Running' | 'Succeeded' | 'Failed'

export interface StageResult {
  stage: number
  label: string
  state: StageState
  written: number
  warnings: string[]
}

export type RunMode = 'dryRun' | 'apply'

export interface Run {
  runId: string
  mode: RunMode
  target: string
  state: RunState
  snapshotId: string | null
  stages: StageResult[]
  problems: string[]
}
