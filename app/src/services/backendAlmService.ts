import type { AlmService } from './almService'
import { normaliseDiff, normalisePlan, normaliseRun } from './normalise'
import type { DiffModel, EnvironmentRef, Plan, Run, RunListItem, SelectionItem } from '../types/alm'

// Talks to the ALM backend described in docs/architecture.md: the deployed Function (local dev,
// VITE_ALM_SOURCE=backend) or the local runner (VITE_ALM_SOURCE=local, base URL /api).
//
// In a code app, an external API is reached through a connector (custom connector or
// the platform's HTTP infrastructure) so DLP and Entra auth apply. This adapter uses
// fetch against a base URL for now; wire it to the generated connector client once the
// backend and its custom connector exist. The method shapes already match the contract,
// so that swap does not touch the UI.

export async function json<T>(res: Response): Promise<T> {
  if (!res.ok) {
    let message = `${res.status} ${res.statusText}`
    try {
      const body = await res.json()
      if (body?.error?.message) message = body.error.message
    } catch {
      /* keep status text */
    }
    throw new Error(message)
  }
  return res.json() as Promise<T>
}

export class BackendAlmService implements AlmService {
  constructor(
    private readonly baseUrl: string,
    private readonly headers: Record<string, string> = {},
  ) {
    if (!baseUrl) throw new Error('Backend URL is not set. Set VITE_ALM_BACKEND_URL.')
  }

  private get(path: string): Promise<Response> {
    return fetch(`${this.baseUrl.replace(/\/$/, '')}${path}`, { headers: this.headers })
  }

  private post(path: string, body: unknown): Promise<Response> {
    return fetch(`${this.baseUrl.replace(/\/$/, '')}${path}`, {
      method: 'POST',
      headers: { ...this.headers, 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    })
  }

  async listEnvironments(): Promise<EnvironmentRef[]> {
    return json(await this.get('/environments'))
  }

  async compare(sourceId: string, targetId: string): Promise<DiffModel> {
    return normaliseDiff(await json<DiffModel>(await this.post('/compare', { sourceEnvId: sourceId, targetEnvId: targetId })))
  }

  async plan(diff: DiffModel, selection?: SelectionItem[], includeDependencies = true): Promise<Plan> {
    // diffId lets the local runner plan from the compare it already holds instead of reading
    // both environments again; the Function ignores it and compares afresh.
    return normalisePlan(await json<Plan>(
      await this.post('/plan', {
        sourceEnvId: diff.source,
        targetEnvId: diff.target,
        diffId: diff.diffId,
        selection,
        includeDependencies,
      }),
    ))
  }

  async apply(plan: Plan, mode: 'dryRun' | 'apply', approved: boolean): Promise<Run> {
    // The backend rebuilds context from source and target, so it needs the selection,
    // not a stored plan id. It runs the plan and returns the run record directly.
    const selection = plan.operations.map((o) => ({ table: o.table, matchKey: o.matchKey }))
    return normaliseRun(await json<Run>(
      await this.post('/apply', {
        sourceEnvId: plan.source,
        targetEnvId: plan.target,
        selection,
        mode,
        approved,
        idempotencyKey: crypto.randomUUID(),
      }),
    ))
  }

  async listRuns(): Promise<RunListItem[]> {
    return json(await this.get('/runs'))
  }

  async getRun(runId: string): Promise<Run> {
    return normaliseRun(await json<Run>(await this.get(`/run/${runId}`)))
  }

  async rollback(runId: string): Promise<Run> {
    return normaliseRun(await json<Run>(await this.post(`/run/${runId}/rollback`, {})))
  }
}
