import { useCallback, useEffect, useState } from 'react'
import { AddRegular, ArrowSyncRegular, EditRegular } from '@fluentui/react-icons'
import { Button, KeyValue, Notice, Panel, Skeleton, StatusLabel, type StatusKind } from '../ui'
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

// Local runner only. Enter each environment's app registration, then run the checks one by one;
// environments that pass can be compared.

type Step = 'details' | 'checks'

function envStatus(env: SetupEnvironment, setup: SetupState): { label: string; kind: StatusKind } {
  const failed = setup.checks.find((c) => env.checks[c.id]?.status === 'fail')
  if (failed) return { label: `${failed.title} failed`, kind: 'failed' }
  if (env.ready) {
    const warned = setup.checks.some((c) => env.checks[c.id]?.status === 'warn')
    return warned ? { label: 'Ready, with warnings', kind: 'blocked' } : { label: 'Ready', kind: 'done' }
  }
  return { label: 'Not checked yet', kind: 'skipped' }
}

export function SetupPage({ onReady }: { onReady: () => void }) {
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
      return { ...s, environments: exists ? s.environments.map((e) => (e.id === env.id ? env : e)) : [...s.environments, env] }
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
      <Notice tone="error" title="Cannot reach the local runner">
        {error}. Start it again with ContactCenterALM-LocalRunner.exe or scripts/run-local.ps1.
      </Notice>
    ) : (
      <Skeleton height={320} />
    )
  }

  const env = selectedId && selectedId !== 'new' ? setup.environments.find((e) => e.id === selectedId) ?? null : null
  const readyCount = setup.environments.filter((e) => e.ready).length
  const checksStarted = !!env && Object.keys(env.checks).length > 0

  return (
    <div className="stack">
      <div className="page-head">
        <div>
          <h1 className="t-h2">Set up environments</h1>
          <p className="page-head__lead">
            Enter the app registration the client gave you for each environment, then check it step by step. Nothing here
            creates anything in Entra.
          </p>
        </div>
      </div>

      {error && (
        <Notice tone="error" title="That did not work" onDismiss={() => setError(null)}>
          {error}
        </Notice>
      )}

      <div className="workspace">
        <div className="stack">
          <Panel
            title={env ? `${env.name}: app registration` : 'New environment: app registration'}
            actions={
              step === 'checks' && env ? (
                <Button size="sm" variant="secondary" leadingIcon={<EditRegular />} disabled={busy} onClick={() => setStep('details')}>
                  Edit
                </Button>
              ) : undefined
            }
          >
            {step === 'details' ? (
              <EnvironmentForm
                key={selectedId ?? 'none'}
                existing={env}
                others={setup.environments}
                takenIds={setup.environments.map((e) => e.id)}
                busy={busy}
                onSave={save}
                onDelete={env ? () => void remove(env) : undefined}
              />
            ) : (
              env && (
                <KeyValue
                  items={[
                    { label: 'Address', value: env.url },
                    { label: 'Tenant', value: env.tenantId },
                    { label: 'Client ID', value: env.clientId },
                    { label: 'Secret', value: env.hasSecret ? 'Saved' : 'Missing: edit to enter it' },
                  ]}
                />
              )
            )}
          </Panel>

          {step === 'checks' && env && (
            <Panel
              title="Checks"
              description="Run in order; each stops the next when it fails and says what to ask the client for."
              actions={
                <Button size="sm" variant={checksStarted ? 'secondary' : 'primary'} leadingIcon={<ArrowSyncRegular />} busy={busy} onClick={() => void runChecks(env.id)}>
                  {checksStarted ? 'Check again' : 'Run checks'}
                </Button>
              }
            >
              <CheckList definitions={setup.checks} results={env.checks} runningId={runningId} />
              {env.ready && !busy && (
                <Notice
                  tone="success"
                  title={`${env.name} is ready`}
                  style={{ marginTop: 'var(--space-4)' }}
                  actions={
                    readyCount >= 2 ? (
                      <Button size="sm" icon onClick={onReady}>
                        Compare environments
                      </Button>
                    ) : (
                      <Button size="sm" leadingIcon={<AddRegular />} onClick={() => select('new')}>
                        Add the other environment
                      </Button>
                    )
                  }
                >
                  {readyCount >= 2 ? 'It can now be compared.' : 'Comparing needs two ready environments.'}
                </Notice>
              )}
            </Panel>
          )}
        </div>

        <aside className="rail" aria-label="Environments">
          <Panel title="Environments" titleAs="h2">
            <ul className="env-list">
              {setup.environments.map((e) => {
                const st = envStatus(e, setup)
                return (
                  <li key={e.id}>
                    <button type="button" className={`env-item${selectedId === e.id ? ' env-item--selected' : ''}`} onClick={() => select(e.id)} disabled={busy} aria-current={selectedId === e.id}>
                      <span className="env-item__name">{e.name}</span>
                      <StatusLabel kind={st.kind} muted>{st.label}</StatusLabel>
                    </button>
                  </li>
                )
              })}
            </ul>
            <div className="rail-actions" style={{ marginTop: 'var(--space-4)' }}>
              <Button variant={selectedId === 'new' ? 'primary' : 'secondary'} size="sm" leadingIcon={<AddRegular />} disabled={busy} onClick={() => select('new')}>
                Add environment
              </Button>
            </div>
            <p className="store-note" style={{ marginTop: 'var(--space-4)' }}>
              Profile <strong>{setup.profile}</strong>.{' '}
              {setup.secretStorage === 'dpapi' ? 'Secrets are encrypted for your Windows user in' : 'Secrets are kept in memory for this session only. Settings are in'}{' '}
              <code>{setup.storePath}</code>
            </p>
          </Panel>
        </aside>
      </div>
    </div>
  )
}
