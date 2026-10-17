import { useEffect, useState } from 'react'
import { AppFooter, AppHeader, Link, Tabs, ThemeToggle } from './ui'
import { MigratePage } from './pages/MigratePage'
import { HistoryPage } from './pages/HistoryPage'
import { SetupPage } from './pages/SetupPage'
import { useMigration } from './hooks/useMigration'
import { getSetup, isLocalRunner } from './services/localSetup'
import { getAlmService } from './services'
import { brand } from './brand'
import './styles/app.css'

type Page = 'migrate' | 'history' | 'setup'

export default function App() {
  const m = useMigration()
  const hasHistory = !!getAlmService().listRuns
  // The local runner opens on Setup until two environments pass their checks.
  const [page, setPage] = useState<Page | null>(isLocalRunner ? null : 'migrate')

  useEffect(() => {
    document.title = brand.browserTitle
    if (!isLocalRunner) return
    getSetup()
      .then((s) => setPage(s.environments.filter((e) => e.ready).length >= 2 ? 'migrate' : 'setup'))
      .catch(() => setPage('setup'))
  }, [])

  const tabs = [
    { id: 'migrate', label: 'Migrate' },
    ...(hasHistory ? [{ id: 'history', label: 'History' }] : []),
    ...(isLocalRunner ? [{ id: 'setup', label: 'Setup' }] : []),
  ]

  return (
    <div className="app">
      <AppHeader
        productName={brand.productName}
        subtitle={brand.subtitle}
        nav={
          tabs.length > 1 && page ? (
            <Tabs tone="heavy" items={tabs} selected={page} onSelect={(id) => setPage(id as Page)} idBase="main-nav" />
          ) : undefined
        }
        actions={<ThemeToggle tone="heavy" label="Dark" />}
      />
      <main className="app-main" id="main">
        {page === 'migrate' && <MigratePage m={m} />}
        {page === 'history' && <HistoryPage runs={m.runs} environments={m.environments} onRefresh={m.refreshRuns} />}
        {page === 'setup' && (
          <SetupPage
            onReady={() => {
              // Environments set up just now: reload the list the migration flow picks from.
              window.location.reload()
            }}
          />
        )}
      </main>
      <AppFooter
        left={<span>{brand.footer.disclaimer}</span>}
        right={
          <span className="row">
            <span>{brand.footer.creator}</span>
            <Link href={brand.footer.mailHref}>Mail</Link>
            <Link href={brand.footer.teamsHref} target="_blank" rel="noreferrer">Teams</Link>
            <Link href={brand.footer.sourceHref} target="_blank" rel="noreferrer">Source</Link>
          </span>
        }
      />
    </div>
  )
}
