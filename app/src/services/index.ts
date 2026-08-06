import type { AlmService } from './almService'
import { MockAlmService } from './mockAlmService'
import { BackendAlmService } from './backendAlmService'
import { ConnectorAlmService } from './connectorAlmService'

let instance: AlmService | null = null

export function getAlmService(): AlmService {
  if (instance) return instance

  const source = import.meta.env.VITE_ALM_SOURCE ?? 'mock'
  switch (source) {
    case 'connector':
      // Published app: calls the backend through the custom connector.
      instance = new ConnectorAlmService()
      break
    case 'backend':
      // Local dev: direct HTTP to the deployed Function (needs CORS).
      instance = new BackendAlmService(import.meta.env.VITE_ALM_BACKEND_URL ?? '')
      break
    default:
      // Standalone: in-memory sample data.
      instance = new MockAlmService()
  }
  return instance
}

export type { AlmService }
