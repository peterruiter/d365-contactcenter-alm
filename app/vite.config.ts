import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// Code apps are served from the Power Apps host. base stays './' so assets resolve
// under the app path the platform assigns at publish time.
export default defineConfig({
  base: './',
  plugins: [react()],
  server: { port: 3000 },
  build: { outDir: 'dist', sourcemap: true },
})
