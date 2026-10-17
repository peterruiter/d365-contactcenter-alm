import { execSync } from 'node:child_process'
import { readFileSync } from 'node:fs'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// Which build this is, shown in the app and compared with the latest release by the local runner.
// The build number is the commit count on the branch: it only goes up. The release script sets
// CCALM_BUILD_* so the app and the build.json it publishes carry exactly the same values.
function git(args: string): string {
  try {
    return execSync(`git ${args}`, { stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim()
  } catch {
    return ''
  }
}
const pkg = JSON.parse(readFileSync(new URL('./package.json', import.meta.url), 'utf8')) as { version: string }
const buildInfo = {
  version: process.env.CCALM_BUILD_VERSION || pkg.version,
  build: Number(process.env.CCALM_BUILD_NUMBER || git('rev-list --count HEAD') || 0),
  commit: process.env.CCALM_BUILD_COMMIT || git('rev-parse --short HEAD') || 'unknown',
  builtAt: process.env.CCALM_BUILD_AT || new Date().toISOString(),
}

// Code apps are served from the Power Apps host. base stays './' so assets resolve
// under the app path the platform assigns at publish time.
//
// Mode "runner" (.env.runner) is the local runner build: it goes to dist-runner so it never
// overwrites the dist that pac code push publishes, and in dev it proxies /api to the runner.
export default defineConfig(({ mode }) => ({
  base: './',
  plugins: [react()],
  define: { __CCALM_BUILD__: JSON.stringify(buildInfo) },
  // strictPort so a taken 3000 fails loudly instead of silently moving to 3001+, which is not
  // in the Function App's CORS allow-list - that mismatch surfaces as an opaque "Failed to fetch",
  // not a helpful CORS error, since the browser never exposes response details on a CORS rejection.
  server: {
    port: 3000,
    strictPort: true,
    proxy: mode === 'runner' ? { '/api': 'http://localhost:7171' } : undefined,
  },
  // No source maps in the runner build: it ships in the release zip, where they only add size.
  build: { outDir: mode === 'runner' ? 'dist-runner' : 'dist', sourcemap: mode !== 'runner' },
}))
