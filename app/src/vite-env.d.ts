/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_ALM_SOURCE?: 'mock' | 'backend'
  readonly VITE_ALM_BACKEND_URL?: string
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}
