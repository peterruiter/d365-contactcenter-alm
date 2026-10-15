/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_ALM_SOURCE?: 'mock' | 'backend' | 'connector' | 'local'
  readonly VITE_ALM_BACKEND_URL?: string
  readonly VITE_BRAND?: 'capgemini' | 'powerpete'
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}
