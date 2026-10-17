import { json } from './backendAlmService'
import type { EnvRole } from '../types/alm'
import type { UpdateInfo } from '../buildInfo'

// Setup API of the local runner (backend/local-runner/Server.ps1). Only used when
// VITE_ALM_SOURCE=local. Secrets go in, never come back out: the runner only reports hasSecret.

export const isLocalRunner = import.meta.env.VITE_ALM_SOURCE === 'local'

export type CheckStatus = 'pass' | 'warn' | 'fail'

export interface CheckDefinition {
  id: string
  title: string
  description: string
}

export interface CheckResult {
  status: CheckStatus
  summary: string
  detail: string[]
  fix: string | null
  at: string
}

export interface SetupEnvironment {
  id: string
  name: string
  url: string
  tenantId: string
  clientId: string
  hasSecret: boolean
  role: EnvRole
  requireApproval: boolean
  checks: Record<string, CheckResult | undefined>
  ready: boolean
}

export interface SetupState {
  profile: string
  storePath: string
  secretStorage: 'dpapi' | 'session'
  checks: CheckDefinition[]
  environments: SetupEnvironment[]
}

export interface EnvironmentInput {
  name: string
  url: string
  tenantId: string
  clientId: string
  /** New secret. Leave empty to keep the saved one. */
  clientSecret?: string
  /** Reuse the saved secret of another environment (same app registration). */
  secretFrom?: string
  role: EnvRole
  requireApproval: boolean
}

const headers = { 'X-CcAlm-Local': '1' }

export async function getSetup(): Promise<SetupState> {
  return json(await fetch('/api/setup', { headers }))
}

export async function saveEnvironment(id: string, input: EnvironmentInput): Promise<SetupEnvironment> {
  return json(
    await fetch(`/api/setup/environments/${id}`, {
      method: 'PUT',
      headers: { ...headers, 'Content-Type': 'application/json' },
      body: JSON.stringify(input),
    }),
  )
}

export async function deleteEnvironment(id: string): Promise<void> {
  await json(await fetch(`/api/setup/environments/${id}`, { method: 'DELETE', headers }))
}

export async function runCheck(id: string, checkId: string): Promise<SetupEnvironment> {
  return json(await fetch(`/api/setup/environments/${id}/checks/${checkId}`, { method: 'POST', headers }))
}

/** The latest local runner release on GitHub, as the runner last saw it. `refresh` asks again now. */
export async function getUpdate(refresh = false): Promise<UpdateInfo> {
  return json(await fetch(`/api/update${refresh ? '?refresh=1' : ''}`, { headers }))
}
