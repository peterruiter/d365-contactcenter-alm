import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// Code apps are served from the Power Apps host. base stays './' so assets resolve
// under the app path the platform assigns at publish time.
//
// Mode "runner" (.env.runner) is the local runner build: it goes to dist-runner so it never
// overwrites the dist that pac code push publishes, and in dev it proxies /api to the runner.
export default defineConfig(({ mode }) => ({
  base: './',
  plugins: [react()],
  // strictPort so a taken 3000 fails loudly instead of silently moving to 3001+, which is not
  // in the Function App's CORS allow-list - that mismatch surfaces as an opaque "Failed to fetch",
  // not a helpful CORS error, since the browser never exposes response details on a CORS rejection.
  server: {
    port: 3000,
    strictPort: true,
    proxy: mode === 'runner' ? { '/api': 'http://localhost:7171' } : undefined,
  },
  build: { outDir: mode === 'runner' ? 'dist-runner' : 'dist', sourcemap: true },
}))
