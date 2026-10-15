import { useCallback, useEffect, useState } from 'react'
import { Button, MessageBar, MessageBarBody, MessageBarTitle, Spinner, Text } from '@fluentui/react-components'
import { AddRegular, ArrowRightRegular, ArrowSyncRegular, EditRegular } from '@fluentui/react-icons'
import { EnvironmentForm } from '../components/setup/EnvironmentForm'
import { CheckList } from '../components/setup/CheckList'
import {
  deleteEnvironment,
  getSetup,
  runCheck,
  saveEnvironment,
  type EnvironmentInput,
  type SetupEnvironment,
  type SetupState,
} from '../services/localSetup'

// Local runner only. Add each environment's app registration, then run the checks one by one;
// environments that pass show up in Compare.

type Step = 'details' | 'checks'

function envStatus(env: SetupEnvironment, setup: SetupState): { label: string; tone: 'done' | 'warning' | 'error' | 'pending' } {
  const failed = setup.checks.find((c) => env.checks[c.id]?.status === 'fail')
  if (failed) return { label: `${failed.title} failed`, tone: 'error' }
  if (env.ready) {
    const warned = setup.checks.some((c) => env.checks[c.id]?.status === 'warn')
    return warned ? { label: 'Ready, with warnings', tone: 'warning' } : { label: 'Ready', tone: 'done' }
  }
  return { label: 'Not checked yet', tone: 'pending' }
}

export function SetupPage({ onGoCompare }: { onGoCompare: () => void }) {
  const [setup, setSetup] = useState<SetupState | null>(null)
  const [selectedId, setSelectedId] = useState<string | 'new' | null>(null)
  const [step, setStep] = useState<Step>('details')
  const [runningId, setRunningId] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    getSetup()
      .then((s) => {
        setSetup(s)
        const first = s.environments.find((e) => !e.ready) ?? s.environments[0]
        if (first) {
          setSelectedId(first.id)
          setStep(Object.keys(first.checks).length > 0 ? 'checks' : 'details')
        } else {
          setSelectedId('new')
        }
      })
      .catch((e) => setError(e instanceof Error ? e.message : String(e)))
  }, [])

  const upsert = useCallback((env: SetupEnvironment) => {
    setSetup((s) => {
      if (!s) return s
      const exists = s.environments.some((e) => e.id === env.id)
      return {
        ...s,
        environments: exists ? s.environments.map((e) => (e.id === env.id ? env : e)) : [...s.environments, env],
      }
    })
  }, [])

  const runChecks = useCallback(
    async (id: string) => {
      if (!setup) return
      setError(null)
      setBusy(true)
      try {
        // One at a time, stopping at the first failure: a later check means nothing when an
        // earlier one failed (no point testing table access without a token).
        for (const def of setup.checks) {
          setRunningId(def.id)
          const env = await runCheck(id, def.id)
          upsert(env)
          if (env.checks[def.id]?.status === 'fail') break
        }
      } catch (e) {
        setError(e instanceof Error ? e.message : String(e))
      } finally {
        setRunningId(null)
        setBusy(false)
      }
    },
    [setup, upsert],
  )

  const save = async (id: string, input: EnvironmentInput) => {
    setError(null)
    setBusy(true)
    try {
      const env = await saveEnvironment(id, input)
      upsert(env)
      setSelectedId(env.id)
      setStep('checks')
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
      setBusy(false)
      return
    }
    setBusy(false)
    await runChecks(id)
  }

  const remove = async (env: SetupEnvironment) => {
    if (!window.confirm(`Remove ${env.name} and its saved secret from this profile?`)) return
    setBusy(true)
    try {
      await deleteEnvironment(env.id)
      setSetup((s) => (s ? { ...s, environments: s.environments.filter((e) => e.id !== env.id) } : s))
      setSelectedId('new')
      setStep('details')
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  const select = (id: string | 'new') => {
    if (busy) return
    setSelectedId(id)
    setError(null)
    const env = setup?.environments.find((e) => e.id === id)
    setStep(env && Object.keys(env.checks).length > 0 ? 'checks' : 'details')
  }

  if (!setup) {
    return error ? (
      <MessageBar intent="error">
        <MessageBarBody>
          <MessageBarTitle>Cannot reach the local runner</MessageBarTitle>
          {error}. Start it with ./scripts/run-local.ps1.
        </MessageBarBody>
      </MessageBar>
    ) : (
      <Spinner label="Loading setup…" />
    )
  }

  const env = selectedId && selectedId !== 'new' ? setup.environments.find((e) => e.id === selectedId) ?? null : null
  const readyCount = setup.environments.filter((e) => e.ready).length
  const checksStarted = !!env && Object.keys(env.checks).length > 0

  return (
    <div className="layout">
      <div className="layout-main">
        {error && (
          <MessageBar intent="error" className="section">
            <MessageBarBody>{error}</MessageBarBody>
          </MessageBar>
        )}

        <div className="section panel">
          <div className="section-head">
            <span className="section-title">
              <span className="setup-step-num">1</span>
              {env ? `${env.name} - app registration` : 'New environment - app registration'}
            </span>
            {step === 'checks' && env && (
              <Button appearance="subtle" icon={<EditRegular />} disabled={busy} onClick={() => setStep('details')}>
                Edit
              </Button>
            )}
          </div>
          {step === 'details' ? (
            <>
              <Text block className="section-hint setup-intro">
                Enter what the client gave you. The app registration has to be an Application user in this environment;
                nothing here creates anything in Entra.
              </Text>
              <EnvironmentForm
                key={selectedId ?? 'none'}
                existing={env}
                others={setup.environments}
                takenIds={setup.environments.map((e) => e.id)}
                busy={busy}
                onSave={save}
                onDelete={env ? () => remove(env) : undefined}
              />
            </>
          ) : (
            env && (
              <dl className="setup-summary">
                <dt>URL</dt>
                <dd>{env.url}</dd>
                <dt>Tenant</dt>
                <dd>{env.tenantId}</dd>
                <dt>Client ID</dt>
                <dd>{env.clientId}</dd>
                <dt>Secret</dt>
                <dd>{env.hasSecret ? 'Saved' : 'Missing - edit to enter it'}</dd>
              </dl>
            )
          )}
        </div>

        {step === 'checks' && env && (
          <div className="section panel">
            <div className="section-head">
              <span className="section-title">
                <span className="setup-step-num">2</span>Checks
              </span>
              <Button
                appearance={checksStarted ? 'secondary' : 'primary'}
                icon={busy ? <Spinner size="tiny" /> : <ArrowSyncRegular />}
                disabled={busy}
                onClick={() => runChecks(env.id)}
              >
                {checksStarted ? 'Run again' : 'Run checks'}
              </Button>
            </div>
            <CheckList definitions={setup.checks} results={env.checks} runningId={runningId} />

            {env.ready && !busy && (
              <MessageBar intent="success" className="setup-done">
                <MessageBarBody>
                  <MessageBarTitle>{env.name} is ready</MessageBarTitle>
                  {readyCount >= 2
                    ? 'It shows up in Compare.'
                    : 'Compare needs two ready environments - add the other side next.'}
                </MessageBarBody>
              </MessageBar>
            )}
            {env.ready && !busy && (
              <div className="actions">
                {readyCount >= 2 && (
                  <Button appearance="primary" icon={<ArrowRightRegular />} iconPosition="after" onClick={onGoCompare}>
                    Go to Compare
                  </Button>
                )}
                <Button appearance={readyCount >= 2 ? 'secondary' : 'primary'} icon={<AddRegular />} onClick={() => select('new')}>
                  Add another environment
                </Button>
              </div>
            )}
          </div>
        )}
      </div>

      <aside className="wizard">
        <Text weight="semibold" size={300} block style={{ marginBottom: 'var(--space-xs)' }}>
          Environments
        </Text>
        <ul className="setup-env-list">
          {setup.environments.map((e) => {
            const st = envStatus(e, setup)
            return (
              <li key={e.id}>
                <button
                  type="button"
                  className={`setup-env${selectedId === e.id ? ' setup-env-selected' : ''}`}
                  onClick={() => select(e.id)}
                  disabled={busy}
                >
                  <span className="setup-env-name">{e.name}</span>
                  <span className={`setup-env-status tone-${st.tone}`}>{st.label}</span>
                </button>
              </li>
            )
          })}
        </ul>
        <Button
          appearance={selectedId === 'new' ? 'primary' : 'secondary'}
          icon={<AddRegular />}
          disabled={busy}
          onClick={() => select('new')}
          style={{ width: '100%', marginTop: 'var(--space-2xs)' }}
        >
          Add environment
        </Button>
        <div className="setup-store">
          Profile <b>{setup.profile}</b>
          <br />
          {setup.secretStorage === 'dpapi'
            ? 'Secrets encrypted for your Windows user in'
            : 'Secrets kept in memory for this session only. Settings in'}
          <br />
          <code>{setup.storePath}</code>
        </div>
      </aside>
    </div>
  )
}
