import { useState } from 'react'
import { FluentProvider, Text, Switch } from '@fluentui/react-components'
import { lightTheme, darkTheme } from './theme'
import { ComparePage } from './pages/ComparePage'
import './styles/app.css'

export default function App() {
  const prefersDark = typeof window !== 'undefined' && window.matchMedia?.('(prefers-color-scheme: dark)').matches
  const [dark, setDark] = useState<boolean>(!!prefersDark)

  return (
    <FluentProvider theme={dark ? darkTheme : lightTheme} style={{ height: '100%' }}>
      <div className="app-shell">
        <header className="app-header">
          <div className="app-title" style={{ flex: 1 }}>
            <Text size={500} weight="bold">Contact Center ALM</Text>
            <Text size={200} style={{ color: 'var(--colorNeutralForeground3)' }}>
              Compare and move routing and channel config across environments
            </Text>
          </div>
          <Switch checked={dark} onChange={(_, d) => setDark(d.checked)} label="Dark" />
        </header>
        <main className="app-body">
          <ComparePage />
        </main>
      </div>
    </FluentProvider>
  )
}
