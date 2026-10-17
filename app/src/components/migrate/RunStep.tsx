import { useState } from 'react'
import { ArrowCounterclockwiseRegular } from '@fluentui/react-icons'
import { Button, Dialog, FilterChips, KeyValue, Notice, Panel, ProgressBar, StatusLabel } from '../../ui'
import { ACTIVE_RUN_STATES } from '../../types/alm'
import type { Migration } from '../../hooks/useMigration'
import { ApplyDialog } from './ApplyDialog'
import { fullName, isProblem, OP_LABEL, OUTCOME, PHASE_LABEL, plural, RUN_STATE } from './labels'

/** Step 4: what a dry run or an apply did, record by record. */
export function RunStep({ m }: { m: Migration }) {
  const run = m.run
  const [show, setShow] = useState<string[]>(['all'])
  const [applyOpen, setApplyOpen] = useState(false)
  const [rollbackOpen, setRollbackOpen] = useState(false)
  if (!run) return null

  const dry = run.mode === 'dryRun'
  const active = ACTIVE_RUN_STATES.includes(run.state)
  const interrupted = run.state === 'Interrupted'
  const s = run.summary
  const progress = run.progress
  const measurable = !!progress && progress.total > 0 && (run.phase === 'writing' || run.phase === 'linking' || run.phase === 'continuing')
  const notMoved = s.skipped + s.blocked
  const problemsOnly = show.includes('problems')
  const rolledBack = run.state === 'RolledBack'
  const canApply = dry && !active && !interrupted && m.plan && m.plan.summary.ready > 0
  const canRollback = !dry && !active && !!run.snapshotId && !rolledBack

  const targetName = m.target?.name ?? run.target
  const title =
    run.state === 'RollingBack'
      ? `Rolling back in ${targetName}`
      : active
        ? dry
          ? 'Dry run in progress'
          : `Applying to ${targetName}`
        : interrupted
          ? `${dry ? 'Dry run' : 'Apply'} interrupted`
          : rolledBack
            ? `Rolled back in ${targetName}`
            : dry
              ? 'Dry run finished'
              : `Applied to ${targetName}`

  return (
    <div className="workspace">
      <div className="stack">
        <div className="run-hero">
          <div>
            <h2 className="run-hero__title">{title}</h2>
            <p className="muted">
              {dry ? 'Nothing was written. This is exactly what applying the plan would do.' : `${m.source?.name ?? run.source} to ${m.target?.name ?? run.target}.`}
            </p>
          </div>
          <StatusLabel kind={RUN_STATE[run.state].kind} size="md">
            {RUN_STATE[run.state].label}
          </StatusLabel>
        </div>

        {active && (
          <Panel>
            <div className="stack stack--tight">
              <ProgressBar
                label={run.phase ? PHASE_LABEL[run.phase] : 'Working'}
                value={measurable ? progress?.done : undefined}
                max={measurable ? progress?.total : undefined}
                showValue={measurable}
                valueText={measurable ? `${progress?.done} of ${progress?.total}` : undefined}
              />
              {progress?.current && <p className="t-body-small">{progress.current}</p>}
              <p className="muted t-body-small">
                This runs on the {import.meta.env.VITE_ALM_SOURCE === 'local' ? 'local runner' : 'backend'}, not in this page: you can leave and come back, and it carries on.
              </p>
            </div>
          </Panel>
        )}

        {interrupted && (
          <Notice
            tone="warning"
            title="This run stopped before it finished"
            actions={
              m.plan ? (
                <Button size="sm" disabled={m.busy !== null} onClick={() => (dry ? void m.execute('dryRun', false) : setApplyOpen(true))}>
                  Continue
                </Button>
              ) : undefined
            }
          >
            {run.message ?? 'Continuing compares again and writes only what is still missing.'}
            {!m.plan && ' Compare and check the plan again to continue it.'}
          </Notice>
        )}

        {run.state === 'Failed' && run.message && (
          <Notice tone="error" title="The run failed" live="none">
            {run.message}
          </Notice>
        )}

        {rolledBack && run.cleanup && (
          <Notice tone={run.cleanup.unresolved.length ? 'warning' : 'success'} title="Rollback finished" live="none">
            {plural(run.cleanup.restored, 'record')} restored to how they were, {plural(run.cleanup.deleted, 'created record')} deleted.
            {run.cleanup.unresolved.length > 0 && (
              <ul className="rail-list" style={{ marginTop: 'var(--space-2)' }}>
                {run.cleanup.unresolved.map((u, i) => (
                  <li key={i}>{u}</li>
                ))}
              </ul>
            )}
          </Notice>
        )}

        <div className="stats">
          <div className="stat"><span className="stat__num">{s.created}</span><span className="stat__label">{dry ? 'would be created' : 'created'}</span></div>
          <div className="stat"><span className="stat__num">{s.updated}</span><span className="stat__label">{dry ? 'would be updated' : 'updated'}</span></div>
          <div className="stat"><span className="stat__num">{s.linked}</span><span className="stat__label">{dry ? 'links to set' : 'linked'}</span></div>
          <div className="stat"><span className="stat__num">{notMoved}</span><span className="stat__label">not moved</span></div>
          <div className="stat"><span className="stat__num">{s.failed}</span><span className="stat__label">failed</span></div>
        </div>

        <FilterChips
          single
          aria-label="Show"
          items={[
            { id: 'all', label: 'Every record' },
            { id: 'problems', label: 'Problems only', count: notMoved + s.failed, disabled: notMoved + s.failed === 0 },
          ]}
          selected={show}
          onChange={(v) => setShow(v.length ? v : ['all'])}
        />

        {run.stages.length === 0 && <p className="muted">There was nothing to move.</p>}
        {run.stages.map((st) => {
          const items = st.items.filter((i) => !problemsOnly || isProblem(i.outcome))
          if (!items.length) return null
          return (
            <section className="stage" key={st.stage} aria-labelledby={`run-st-${st.stage}`}>
              <div className="stage__head">
                <span className="stage__num" aria-hidden="true">{st.stage === 99 ? '↺' : st.stage}</span>
                <h3 className="stage__title" id={`run-st-${st.stage}`}>{st.label}</h3>
                <span className="stage__desc">{plural(st.written, 'write')}{dry ? ' simulated' : ''}</span>
              </div>
              <ul className="items tbl__body">
                {items.map((i, idx) => (
                  <li className="item" key={`${i.seq}-${i.op}-${idx}`}>
                    <StatusLabel kind={OUTCOME[i.outcome].kind}>{OUTCOME[i.outcome].label}</StatusLabel>
                    <div>
                      <div className="rec__name">
                        {fullName(i.displayName, i.context)}
                      </div>
                      <div className="item__msg">
                        {i.tableLabel} · {OP_LABEL[i.op]} · {i.message}
                      </div>
                    </div>
                  </li>
                ))}
              </ul>
            </section>
          )
        })}
      </div>

      <aside className="rail" aria-label="Next steps">
        <Panel title="Next" titleAs="h2">
          <div className="rail-actions">
            {canApply && (
              <>
                <Button disabled={m.busy !== null} onClick={() => setApplyOpen(true)}>
                  Apply to {m.target?.name ?? 'target'}
                </Button>
                <p className="muted t-body-small">
                  {run.state === 'Succeeded'
                    ? 'The dry run found no problems.'
                    : 'Records with problems will not be written. Fix them in the plan, or apply the rest.'}
                </p>
              </>
            )}
            {canRollback && (
              <Button variant="secondary" leadingIcon={<ArrowCounterclockwiseRegular />} busy={m.busy === 'rollback'} disabled={m.busy !== null} onClick={() => setRollbackOpen(true)}>
                Roll back this run
              </Button>
            )}
            {active && <p className="muted t-body-small">Actions come back when the run finishes.</p>}
            {m.plan && !rolledBack && !active && (
              <Button variant="secondary" disabled={m.busy !== null} onClick={() => m.setStep('plan')}>
                Back to the plan
              </Button>
            )}
            {!active && (
              <Button variant="secondary" disabled={m.busy !== null} onClick={m.startOver}>
                Start a new comparison
              </Button>
            )}
          </div>
        </Panel>
        <Panel title="Run details" titleAs="h2">
          <KeyValue
            compact
            stacked
            items={[
              { label: 'Run', value: <code>{run.runId}</code> },
              { label: 'Mode', value: dry ? 'Dry run' : 'Apply' },
              ...(run.finishedAt ? [{ label: 'Finished', value: new Date(run.finishedAt).toLocaleString() }] : []),
              ...(run.snapshotId ? [{ label: 'Snapshot', value: 'Kept for rollback' }] : []),
            ]}
          />
        </Panel>
      </aside>

      <ApplyDialog m={m} open={applyOpen} onClose={() => setApplyOpen(false)} />
      <Dialog
        open={rollbackOpen}
        onClose={() => setRollbackOpen(false)}
        title={`Roll back this run in ${m.target?.name ?? run.target}?`}
        description="Every record the run changed is set back to how it was, and every record it created is deleted. Anything Dataverse provisioned on its own for a new workstream goes with it where Dataverse allows; what it refuses is listed afterwards."
        actions={
          <>
            <Button variant="secondary" onClick={() => setRollbackOpen(false)}>
              Keep the changes
            </Button>
            <Button
              busy={m.busy === 'rollback'}
              onClick={async () => {
                await m.rollback()
                setRollbackOpen(false)
              }}
            >
              Roll back
            </Button>
          </>
        }
      />
    </div>
  )
}
