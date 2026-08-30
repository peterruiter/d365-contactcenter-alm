import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// Code apps are served from the Power Apps host. base stays './' so assets resolve
// under the app path the platform assigns at publish time.
export default defineConfig({
  base: './',
  plugins: [react()],
  // strictPort so a taken 3000 fails loudly instead of silently moving to 3001+, which is not
  // in the Function App's CORS allow-list - that mismatch surfaces as an opaque "Failed to fetch",
  // not a helpful CORS error, since the browser never exposes response details on a CORS rejection.
  server: { port: 3000, strictPort: true },
  build: { outDir: 'dist', sourcemap: true },
})
