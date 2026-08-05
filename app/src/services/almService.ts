import type {
  DiffModel,
  EnvironmentRef,
  Plan,
  Run,
  SelectionItem,
} from '../types/alm'

// The single seam between the UI and whatever does the real work.
// mock: in-memory sample data, runs standalone.
// backend: calls the ALM backend (service principal, all four environments).
// Swapping one for the other never touches a component.
export interface AlmService {
  listEnvironments(): Promise<EnvironmentRef[]>
  compare(sourceId: string, targetId: string, tables?: string[]): Promise<DiffModel>
  plan(diff: DiffModel, selection?: SelectionItem[]): Promise<Plan>
  apply(plan: Plan, mode: 'dryRun' | 'apply', approved: boolean): Promise<Run>
  getRun(runId: string): Promise<Run>
  rollback(runId: string): Promise<Run>
}
