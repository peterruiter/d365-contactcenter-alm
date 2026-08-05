import type { AlmService } from './almService'
import type { DiffModel, EnvironmentRef, Plan, Run, SelectionItem } from '../types/alm'

// Talks to the ALM backend described in docs/architecture.md.
//
// In a code app, an external API is reached through a connector (custom connector or
// the platform's HTTP infrastructure) so DLP and Entra auth apply. This adapter uses
// fetch against a base URL for now; wire it to the generated connector client once the
// backend and its custom connector exist. The method shapes already match the contract,
// so that swap does not touch the UI.

async function json<T>(res: Response): Promise<T> {
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
  constructor(private readonly baseUrl: string) {
    if (!baseUrl) throw new Error('Backend URL is not set. Set VITE_ALM_BACKEND_URL.')
  }

  private url(path: string): string {
    return `${this.baseUrl.replace(/\/$/, '')}${path}`
  }

  async listEnvironments(): Promise<EnvironmentRef[]> {
    return json(await fetch(this.url('/environments')))
  }

  async compare(sourceId: string, targetId: string, tables?: string[]): Promise<DiffModel> {
    return json(
      await fetch(this.url('/compare'), {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ sourceEnvId: sourceId, targetEnvId: targetId, tables }),
      }),
    )
  }

  async plan(diff: DiffModel, selection?: SelectionItem[]): Promise<Plan> {
    return json(
      await fetch(this.url('/plan'), {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ sourceEnvId: diff.source, targetEnvId: diff.target, selection }),
      }),
    )
  }

  async apply(plan: Plan, mode: 'dryRun' | 'apply', approved: boolean): Promise<Run> {
    const { runId } = await json<{ runId: string }>(
      await fetch(this.url('/apply'), {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ planId: plan.planId, mode, approved, idempotencyKey: crypto.randomUUID() }),
      }),
    )
    return this.getRun(runId)
  }

  async getRun(runId: string): Promise<Run> {
    return json(await fetch(this.url(`/run/${runId}`)))
  }

  async rollback(runId: string): Promise<Run> {
    return json(
      await fetch(this.url(`/run/${runId}/rollback`), {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: '{}',
      }),
    )
  }
}
