// The ONLY file that touches the generated connector client.
//
// `pac code add-data-source -a <apiName> -c <connectionId>` generates a typed service under
// src/generated/services/, with one method per connector operation - GetEnvironments, Compare,
// Plan, Apply, GetRun, Rollback (from the operationIds in connector/apiDefinition.swagger.json).
// Each method returns IOperationResult<T> ({ success, data, error }), not the raw body; that
// unwrapping happens in connectorAlmService.ts (unwrap()), not here, so this file's job stays
// purely "name the generated service and map its methods 1:1" - nothing else in the app changes
// if the connector is ever regenerated with a different data source name.
//
// src/generated/ is gitignored (it carries org-specific ids), so a fresh checkout has no such
// file. A static import would break every mode, mock included, the moment Vite resolves it; a
// glob that matches nothing is just an empty object, so only connector mode needs the file.

type GeneratedService = Record<string, (...args: unknown[]) => Promise<unknown>>

const generated = import.meta.glob<GeneratedService>('../generated/services/ContactCenterALMService.ts', {
  eager: true,
  import: 'ContactCenterALMService',
})
const ContactCenterALMService = Object.values(generated)[0]

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
  if (!svc) {
    throw new Error(
      'Connector client not generated: src/generated/services/ContactCenterALMService.ts is missing. ' +
        'Run pac code add-data-source for the custom connector, or set VITE_ALM_SOURCE to mock, backend or local.',
    )
  }
  return {
    getEnvironments: () => svc.GetEnvironments(),
    compare: (body) => svc.Compare(body as Record<string, unknown>),
    plan: (body) => svc.Plan(body as Record<string, unknown>),
    apply: (body) => svc.Apply(body as Record<string, unknown>),
    getRun: (id) => svc.GetRun(id),
    rollback: (id) => svc.Rollback(id),
  }
}
