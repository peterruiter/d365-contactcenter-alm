import { useEffect, useState, type ReactNode } from 'react'
import { setConfig, getContext } from '@microsoft/power-apps/app'

// The Power Apps host completes a handshake before the app can reach any data source.
// getContext() resolves once the host is ready. In mock mode (local dev, no host) we
// skip the wait and render immediately, so the app is usable without Power Platform.
export function PowerProvider({ children }: { children: ReactNode }) {
  const [ready, setReady] = useState(import.meta.env.VITE_ALM_SOURCE !== 'backend')
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (import.meta.env.VITE_ALM_SOURCE !== 'backend') return
    let cancelled = false
    setConfig({})
    getContext()
      .then(() => !cancelled && setReady(true))
      .catch((e: unknown) => !cancelled && setError(e instanceof Error ? e.message : String(e)))
    return () => {
      cancelled = true
    }
  }, [])

  if (error) {
    return (
      <div style={{ padding: 24, fontFamily: 'Segoe UI, sans-serif' }}>
        <h2>Power Platform connection failed</h2>
        <p>{error}</p>
        <p>Check that the app is published and the connector is authorised.</p>
      </div>
    )
  }

  if (!ready) return null
  return <>{children}</>
}
