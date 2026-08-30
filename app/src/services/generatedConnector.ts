// The ONLY file that touches the generated connector client.
//
// `pac code add-data-source -a <apiName> -c <connectionId>` generates a typed service under
// src/generated/services/, with one method per connector operation - GetEnvironments, Compare,
// Plan, Apply, GetRun, Rollback (from the operationIds in connector/apiDefinition.swagger.json).
// Each method returns IOperationResult<T> ({ success, data, error }), not the raw body; that
// unwrapping happens in connectorAlmService.ts (unwrap()), not here, so this file's job stays
// purely "name the generated service and map its methods 1:1" - nothing else in the app changes
// if the connector is ever regenerated with a different data source name.

import { ContactCenterALMService } from '../generated/services/ContactCenterALMService'

export interface RawAlmClient {
  getEnvironments(): Promise<unknown>
  compare(body: unknown): Promise<unknown>
  plan(body: unknown): Promise<unknown>
  apply(body: unknown): Promise<unknown>
  getRun(id: string): Promise<unknown>
  rollback(id: string): Promise<unknown>
}

export function getGeneratedClient(): RawAlmClient {
  const svc = ContactCenterALMService
  return {
    getEnvironments: () => svc.GetEnvironments(),
    compare: (body) => svc.Compare(body as Record<string, unknown>),
    plan: (body) => svc.Plan(body as Record<string, unknown>),
    apply: (body) => svc.Apply(body as Record<string, unknown>),
    getRun: (id) => svc.GetRun(id),
    rollback: (id) => svc.Rollback(id),
  }
}
