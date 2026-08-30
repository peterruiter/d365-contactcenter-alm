import type { AlmService } from './almService'
import type { DiffModel, EnvironmentRef, Plan, Run, SelectionItem } from '../types/alm'
import { getGeneratedClient, type RawAlmClient } from './generatedConnector'

// Calls the backend through the generated custom-connector client. The Power Apps host routes
// these calls with Entra auth and DLP applied. This is the path the published app uses.
//
// The request bodies match the backend contract exactly, the same as backendAlmService, so the
// only difference from that adapter is the transport: connector instead of raw fetch.

function unwrap<T>(res: unknown): T {
  // Generated services return IOperationResult<T> ({ success, data, error }) for a connector-backed
  // data source, but tolerate a plain { value } shape too so a generator change does not break the
  // app. A failed call (success: false) throws instead of silently returning undefined data.
  if (res && typeof res === 'object' && !Array.isArray(res)) {
    const obj = res as Record<string, unknown>
    if ('success' in obj && obj.success === false) {
      const err = obj.error
      const message = err instanceof Error ? err.message : typeof err === 'string' ? err : 'Connector call failed.'
      throw new Error(message)
    }
    if ('data' in obj) return obj.data as T
    if ('value' in obj) return obj.value as T
  }
  return res as T
}

export class ConnectorAlmService implements AlmService {
  private readonly client: RawAlmClient

  constructor(client?: RawAlmClient) {
    this.client = client ?? getGeneratedClient()
  }

  async listEnvironments(): Promise<EnvironmentRef[]> {
    return unwrap<EnvironmentRef[]>(await this.client.getEnvironments())
  }

  async compare(sourceId: string, targetId: string, tables?: string[]): Promise<DiffModel> {
    return unwrap<DiffModel>(
      await this.client.compare({ sourceEnvId: sourceId, targetEnvId: targetId, tables }),
    )
  }

  async plan(diff: DiffModel, selection?: SelectionItem[]): Promise<Plan> {
    return unwrap<Plan>(
      await this.client.plan({ sourceEnvId: diff.source, targetEnvId: diff.target, selection }),
    )
  }

  async apply(plan: Plan, mode: 'dryRun' | 'apply', approved: boolean): Promise<Run> {
    const selection = plan.operations.map((o) => ({ table: o.table, matchKey: o.matchKey }))
    return unwrap<Run>(
      await this.client.apply({
        sourceEnvId: plan.source,
        targetEnvId: plan.target,
        selection,
        mode,
        approved,
        idempotencyKey: crypto.randomUUID(),
      }),
    )
  }

  async getRun(runId: string): Promise<Run> {
    return unwrap<Run>(await this.client.getRun(runId))
  }

  async rollback(runId: string): Promise<Run> {
    return unwrap<Run>(await this.client.rollback(runId))
  }
}
