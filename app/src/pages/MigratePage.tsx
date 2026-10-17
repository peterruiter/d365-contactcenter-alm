import { Button, Notice, ProgressBar, Stepper, type StepItem } from '../ui'
import type { Migration, Step } from '../hooks/useMigration'
import { EnvironmentPicker, EnvironmentSummary } from '../components/migrate/EnvironmentPicker'
import { ReviewStep } from '../components/migrate/ReviewStep'
import { PlanStep } from '../components/migrate/PlanStep'
import { RunStep } from '../components/migrate/RunStep'
import { plural } from '../components/migrate/labels'

const ORDER: Step[] = ['environments', 'review', 'plan', 'run']

function steps(m: Migration): StepItem[] {
  const at = ORDER.indexOf(m.step)
  const reached = ORDER.indexOf(m.maxStep)
  const state = (s: Step): StepItem['state'] => {
    const i = ORDER.indexOf(s)
    if (i === at) return 'current'
    if (s === 'plan' && m.plan && m.plan.summary.blocked > 0 && i <= reached) return 'warning'
    if (s === 'run' && m.run && m.run.state !== 'Succeeded' && m.run.state !== 'RolledBack') return 'warning'
    return i <= reached ? 'done' : 'upcoming'
  }
  const d = m.diff?.summary
  return [
    { id: 'environments', label: 'Environments', description: m.source && m.target ? `${m.source.name} to ${m.target.name}` : 'Source and target', state: state('environments') },
    { id: 'review', label: 'Review', description: d ? `${d.missingInTarget} new, ${d.changed} changed` : 'What differs', state: state('review') },
    { id: 'plan', label: 'Plan check', description: m.plan ? `${m.plan.summary.ready} ready, ${m.plan.summary.blocked} blocked` : 'Dependencies and order', state: state('plan') },
    { id: 'run', label: 'Run', description: m.run ? (m.run.mode === 'dryRun' ? 'Dry run done' : 'Applied') : 'Dry run, then apply', state: state('run') },
  ]
}

export function MigratePage({ m }: { m: Migration }) {
  return (
    <div className="stack">
      <div className="page-head">
        <div>
          <h1 className="t-h2">Move contact center configuration</h1>
          <p className="page-head__lead">
            Compare two environments, choose what to move, check every dependency, then dry-run and apply. Records are
            matched by name, never by GUID.
          </p>
        </div>
      </div>

      <Stepper
        steps={steps(m)}
        onSelect={(id) => m.setStep(id as Step)}
        isReachable={(_, i) => i <= ORDER.indexOf(m.maxStep)}
        aria-label="Migration steps"
      />

      {m.error && (
        <Notice tone="error" title="That did not work" onDismiss={m.clearError}>
          {m.error}
        </Notice>
      )}

      {m.step === 'environments' ? (
        <>
          <EnvironmentPicker m={m} />
          {m.busy === 'compare' && <ProgressBar label="Comparing both environments" />}
        </>
      ) : (
        <div className="row row--between">
          <EnvironmentSummary m={m} />
          <div className="row">
            {m.diff && (
              <span className="muted t-body-small">
                {plural(m.diff.summary.missingInTarget + m.diff.summary.changed, 'difference')} found
              </span>
            )}
            <Button size="sm" variant="secondary" disabled={m.busy !== null} onClick={() => m.setStep('environments')}>
              Change environments
            </Button>
          </div>
        </div>
      )}

      {(m.busy === 'dryRun' || m.busy === 'apply') && m.step !== 'run' && <ProgressBar label="Starting the run" />}

      {m.step === 'review' && <ReviewStep m={m} />}
      {m.step === 'plan' && <PlanStep m={m} />}
      {m.step === 'run' && <RunStep m={m} />}
    </div>
  )
}
