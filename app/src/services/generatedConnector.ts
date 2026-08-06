// The ONLY file that touches the generated connector client.
//
// `pac code add-data-source -a <apiName> -c <connectionId>` generates a typed service under
// src/generated/services/, with one method per connector operation. Our operations are
// GetEnvironments, Compare, Plan, Apply, GetRun, Rollback (from the operationIds in
// connector/apiDefinition.swagger.json), so the generated service exposes methods with those
// names returning each operation's JSON response.
//
// After you generate the data source, do two things in this file:
//   1. Set the import below to the generated service.
//   2. Replace the body of getGeneratedClient() with the mapping (see the worked example).
// Nothing else in the app changes.

// 1. After generation, set this import. The exact file and class name come from the connector
//    display name, e.g.:
// import { ContactCenterAlmService } from '../generated/services/ContactCenterAlmService'

export interface RawAlmClient {
  getEnvironments(): Promise<unknown>
  compare(body: unknown): Promise<unknown>
  plan(body: unknown): Promise<unknown>
  apply(body: unknown): Promise<unknown>
  getRun(id: string): Promise<unknown>
  rollback(id: string): Promise<unknown>
}

export function getGeneratedClient(): RawAlmClient {
  // 2. After generation, delete this throw and return the mapping below.
  throw new Error(
    'Connector client not wired yet. Run pac code add-data-source, then map the generated ' +
      'service in src/services/generatedConnector.ts. See docs/getting-started.md, phase B8.',
  )

  // Worked example (uncomment and adjust names to match the generated service):
  //
  // const svc = ContactCenterAlmService
  // return {
  //   getEnvironments: () => svc.GetEnvironments(),
  //   compare: (body) => svc.Compare(body),
  //   plan: (body) => svc.Plan(body),
  //   apply: (body) => svc.Apply(body),
  //   getRun: (id) => svc.GetRun(id),
  //   rollback: (id) => svc.Rollback(id),
  // }
}
