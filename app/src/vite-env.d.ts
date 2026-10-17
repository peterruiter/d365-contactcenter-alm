/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_ALM_SOURCE?: 'mock' | 'backend' | 'connector' | 'local'
  readonly VITE_ALM_BACKEND_URL?: string
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}

/** Stamped at build time by vite.config.ts. */
declare const __CCALM_BUILD__: { version: string; build: number; commit: string; builtAt: string }
