import { useEffect, useState, type ReactNode } from 'react'
import { setConfig, getContext } from '@microsoft/power-apps/app'

// The Power Apps host completes a handshake before the app can reach a connector.
// getContext() resolves once the host (published app) or the `pac code run` proxy (local dev)
// is ready. Connector mode waits for it. Mock and direct-backend modes render immediately,
// since neither needs the connector runtime.
export function PowerProvider({ children }: { children: ReactNode }) {
  const usesConnector = import.meta.env.VITE_ALM_SOURCE === 'connector'
  const [ready, setReady] = useState(!usesConnector)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (!usesConnector) return
    let cancelled = false
    setConfig({})
    getContext()
      .then(() => !cancelled && setReady(true))
      .catch((e: unknown) => !cancelled && setError(e instanceof Error ? e.message : String(e)))
    return () => {
      cancelled = true
    }
  }, [usesConnector])

  if (error) {
    return (
      <div style={{ padding: 24, fontFamily: 'Segoe UI, sans-serif' }}>
        <h2>Power Platform connection failed</h2>
        <p>{error}</p>
        <p>If running locally, start the connector proxy: pac code run. If published, check the app and connector are authorised.</p>
      </div>
    )
  }

  if (!ready) return null
  return <>{children}</>
}
