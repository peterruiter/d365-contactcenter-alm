// Domain types for the Contact Center ALM app. They mirror the backend contract built in
// backend/function-app/Contract.ps1 (shared by the Azure Function and the local runner); keep the
// two in step.

export type EnvRole = 'any' | 'source' | 'target'

export interface EnvironmentRef {
  id: string
  name: string
  url: string
  role: EnvRole
  requireApproval?: boolean
}

// ---------------------------------------------------------------- Compare

/** New in target / changed / only in target / the same / cannot be paired. */
export type RecordStatus = 'MissingInTarget' | 'ExtraInTarget' | 'Changed' | 'Equal' | 'Ambiguous'

export interface FieldDelta {
  /** Column logical name. */
  name: string
  /** Column display name from the environment's metadata. */
  label: string
  /** value: a setting; lookup: which record it points at; definition: ruleset content. */
  kind: 'value' | 'lookup' | 'definition'
  /** As shown in the source (formatted: choice labels, Yes/No, record names). For a definition, a summary of what differs. */
  source: string | null
  /** As shown in the target. Null for a definition. */
  target: string | null
}

export interface DependencyRef {
  table: string
  matchKey: string
  /** "workstream 'Chat'" */
  label: string
  /** The column the dependency comes through, e.g. "Default queue". */
  via: string
  /** Linked in the final pass, because it points at a table written later. */
  deferred: boolean
}

export interface RecordDiff {
  /** Opaque natural key that pairs the record across environments. Never shown. */
  matchKey: string
  status: RecordStatus
  /** What a person calls the record. */
  displayName: string
  /** Where it lives, for records under a parent: "Chat › Contact center routing configuration". */
  context?: string | null
  /** Why an Ambiguous record cannot be paired, and what to do. */
  note?: string | null
  fields: FieldDelta[]
  /** Records this one needs in the target (new and changed records only). */
  dependsOn: DependencyRef[]
}

export interface TableDiff {
  table: string
  /** Plural table label, e.g. "Workstreams". */
  label: string
  /** Functional area, e.g. "Routing". */
  group: string
  stage: number
  records: RecordDiff[]
}

export interface DiffSummary {
  missingInTarget: number
  extraInTarget: number
  changed: number
  equal: number
  ambiguous: number
}

export type DetectType = 'phoneNumber' | 'voiceBot' | 'channelAccount' | 'survey' | 'eventGrid'

export interface DetectFinding {
  type: DetectType
  table: string
  /** Plural table label. */
  label: string
  record: string
  message: string
}

export interface DiffNotice {
  severity: 'info' | 'warning'
  table: string
  message: string
}

export interface DiffModel {
  diffId: string
  source: string
  target: string
  generated: string
  summary: DiffSummary
  tables: TableDiff[]
  detectOnly: DetectFinding[]
  notices: DiffNotice[]
}

// ---------------------------------------------------------------- Plan

export type OpKind = 'create' | 'update' | 'skip-existing'

/** inTarget: already there. createdEarlier: written earlier in this run. linkedLater: set in the final pass. missing: blocks. */
export type DependencyState = 'inTarget' | 'createdEarlier' | 'linkedLater' | 'missing'

export interface PlanDependency {
  table: string
  matchKey: string
  label: string
  via: string
  state: DependencyState
}

export interface PlanFix {
  action: 'include'
  table: string
  matchKey: string
  /** "Add queue 'Mortgages'" */
  label: string
}

export interface PlanBlocker {
  code: string
  message: string
  fix: PlanFix | null
}

export interface PlanOperation {
  seq: number
  stage: number
  table: string
  tableLabel: string
  op: OpKind
  matchKey: string
  displayName: string
  context?: string | null
  status: 'ready' | 'blocked'
  /** Not selected, but needed by a selected record, so added. */
  autoIncluded: boolean
  /** Who needs it, when autoIncluded. */
  neededBy: string[]
  /** Labels of the settings that change. */
  changes: string[]
  dependencies: PlanDependency[]
  blockers: PlanBlocker[]
  warnings: string[]
}

export interface PlanStage {
  stage: number
  label: string
  description?: string | null
}

export interface PlanSummary {
  total: number
  ready: number
  blocked: number
  autoIncluded: number
  creates: number
  updates: number
  links: number
}

export interface IgnoredSelection {
  table: string
  matchKey: string
  displayName: string
  reason: string
}

export interface Plan {
  planId: string
  diffId: string
  source: string
  target: string
  created: string
  summary: PlanSummary
  operations: PlanOperation[]
  ignored: IgnoredSelection[]
  stages: PlanStage[]
}

export interface SelectionItem {
  table: string
  matchKey: string
}

// ---------------------------------------------------------------- Run

export type RunState = 'Succeeded' | 'PartiallyFailed' | 'Failed' | 'RolledBack'
export type RunMode = 'dryRun' | 'apply'

export type ItemOutcome =
  | 'created'
  | 'updated'
  | 'linked'
  | 'unchanged'
  | 'wouldCreate'
  | 'wouldUpdate'
  | 'wouldLink'
  | 'skipped'
  | 'blocked'
  | 'failed'

export interface RunItem {
  seq: number
  table: string
  tableLabel: string
  displayName: string
  context?: string | null
  op: OpKind | 'link'
  outcome: ItemOutcome
  message: string
}

export interface StageResult {
  stage: number
  label: string
  state: 'Succeeded' | 'PartiallyFailed' | 'Failed'
  written: number
  warnings: string[]
  items: RunItem[]
}

export interface RunSummary {
  created: number
  updated: number
  linked: number
  skipped: number
  blocked: number
  failed: number
}

export interface RunCleanup {
  restored: number
  deleted: number
  unresolved: string[]
}

export interface Run {
  runId: string
  mode: RunMode
  source: string
  target: string
  state: RunState
  snapshotId: string | null
  startedAt?: string
  finishedAt?: string
  summary: RunSummary
  stages: StageResult[]
  problems: string[]
  cleanup?: RunCleanup
}

export interface RunListItem {
  runId: string
  mode: string
  source: string
  target: string
  state: RunState
  startedAt?: string
  finishedAt?: string
  summary?: RunSummary
  snapshotId: string | null
}
