import { useState } from 'react'
import { FluentProvider, Switch } from '@fluentui/react-components'
import { lightTheme, darkTheme } from './theme'
import { ComparePage } from './pages/ComparePage'
import './styles/app.css'

export default function App() {
  const [dark, setDark] = useState<boolean>(false)

  return (
    <FluentProvider theme={dark ? darkTheme : lightTheme} style={{ height: '100%' }}>
      <div className={`app-shell${dark ? ' theme-dark' : ''}`}>
        <header className="app-header">
          <div className="brand">
            {/* Wordmark. Drop in the official Capgemini SVG logo here when you have the asset. */}
            <span className="brand-mark" aria-hidden="true" />
            <span className="brand-word">Capgemini</span>
          </div>
          <div className="header-divider" />
          <div className="header-title">
            <span className="header-product">Contact Center ALM</span>
            <span className="header-sub">Compare and move routing and channel config across environments</span>
          </div>
          <div className="header-actions">
            <Switch checked={dark} onChange={(_, d) => setDark(d.checked)} label={dark ? 'Dark' : 'Light'} />
          </div>
        </header>

        <main className="app-body">
          <div className="content">
            <ComparePage />
          </div>
        </main>
      </div>
    </FluentProvider>
  )
}
