import type { AlmService } from './almService'
import { MockAlmService } from './mockAlmService'
import { BackendAlmService } from './backendAlmService'

let instance: AlmService | null = null

export function getAlmService(): AlmService {
  if (instance) return instance

  const source = import.meta.env.VITE_ALM_SOURCE ?? 'mock'
  if (source === 'backend') {
    instance = new BackendAlmService(import.meta.env.VITE_ALM_BACKEND_URL ?? '')
  } else {
    instance = new MockAlmService()
  }
  return instance
}

export type { AlmService }
