import type { DiffModel, EnvironmentRef, Plan, Run, RunListItem, SelectionItem } from '../types/alm'

// The single seam between the UI and whatever does the real work.
// mock: in-memory sample data, runs standalone.
// backend / local: the ALM backend over HTTP (the Function, or the local runner).
// connector: the backend through the custom connector, in the published app.
// Swapping one for the other never touches a component.
export interface AlmService {
  listEnvironments(): Promise<EnvironmentRef[]>
  compare(sourceId: string, targetId: string): Promise<DiffModel>
  /** Builds and preflights a plan. With includeDependencies, records the selection needs are added. */
  plan(diff: DiffModel, selection?: SelectionItem[], includeDependencies?: boolean): Promise<Plan>
  /** Dry run or apply of exactly the plan's operations. */
  apply(plan: Plan, mode: 'dryRun' | 'apply', approved: boolean): Promise<Run>
  getRun(runId: string): Promise<Run>
  rollback(runId: string): Promise<Run>
  /** Recent runs, newest first. Not every backend keeps a list. */
  listRuns?(): Promise<RunListItem[]>
}
