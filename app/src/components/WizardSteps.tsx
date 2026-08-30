import { Spinner, Text } from '@fluentui/react-components'
import { CheckmarkCircleFilled, ErrorCircleFilled, CircleRegular } from '@fluentui/react-icons'
import type { AlmFlow } from '../hooks/useAlmFlow'

type StepState = 'pending' | 'active' | 'done' | 'warning' | 'error'

interface Step {
  key: string
  title: string
  detail: string
  state: StepState
}

function buildSteps(flow: AlmFlow, movableCount: number): Step[] {
  const { phase, busy, error, diff, plan, run } = flow

  const compareErrored = !busy && !!error && phase === 'comparing'
  const planErrored = !busy && !!error && phase === 'planning'
  const runErrored = !busy && !!error && phase === 'running'
  const rollingBack = busy && phase === 'done' && !!run && run.mode === 'apply' && run.state !== 'RolledBack'
  const rollbackErrored = !busy && !!error && phase === 'done' && !!run && run.mode === 'apply' && run.state !== 'RolledBack'

  const steps: Step[] = [
    {
      key: 'compare',
      title: 'Compare',
      state: compareErrored
        ? 'error'
        : phase === 'comparing'
          ? 'active'
          : diff
            ? 'done'
            : 'pending',
      detail: compareErrored
        ? 'Compare failed'
        : phase === 'comparing'
          ? 'Comparing…'
          : diff
            ? `${diff.summary.changed} changed · ${diff.summary.missingInTarget} missing · ${diff.summary.extraInTarget} extra`
            : 'Pick a source and a target',
    },
    {
      key: 'plan',
      title: 'Build plan',
      state: planErrored
        ? 'error'
        : phase === 'planning'
          ? 'active'
          : plan
            ? 'done'
            : 'pending',
      detail: planErrored
        ? 'Plan build failed'
        : phase === 'planning'
          ? 'Building plan…'
          : plan
            ? plan.operations.length > 0
              ? `${plan.operations.length} operations`
              : 'Nothing to move'
            : diff
              ? `${movableCount} movable`
              : 'Compare first',
    },
    {
      key: 'run',
      title: 'Run',
      state: runErrored
        ? 'error'
        : phase === 'running'
          ? 'active'
          : run
            ? run.state === 'Failed'
              ? 'error'
              : run.state === 'PartiallyFailed'
                ? 'warning'
                : 'done'
            : 'pending',
      detail: runErrored
        ? 'Run failed to start'
        : phase === 'running'
          ? 'Running…'
          : run
            ? `${run.mode === 'dryRun' ? 'Dry run' : 'Applied'} · ${run.state}`
            : plan
              ? 'Ready when you are'
              : 'Build a plan first',
    },
  ]

  if (run && run.mode === 'apply') {
    steps.push({
      key: 'rollback',
      title: 'Rollback',
      state: rollbackErrored ? 'error' : rollingBack ? 'active' : run.state === 'RolledBack' ? 'done' : 'pending',
      detail: rollbackErrored
        ? 'Rollback failed'
        : rollingBack
          ? 'Rolling back…'
          : run.state === 'RolledBack'
            ? 'Rolled back'
            : 'Available if needed',
    })
  }

  return steps
}

function StepIcon({ state, index }: { state: StepState; index: number }) {
  if (state === 'active') return <Spinner size="tiny" />
  if (state === 'done') return <CheckmarkCircleFilled className="wiz-icon wiz-icon-done" />
  if (state === 'warning') return <ErrorCircleFilled className="wiz-icon wiz-icon-warning" />
  if (state === 'error') return <ErrorCircleFilled className="wiz-icon wiz-icon-error" />
  return (
    <span className="wiz-step-num">
      <CircleRegular className="wiz-icon wiz-icon-pending" />
      <span>{index + 1}</span>
    </span>
  )
}

export function WizardSteps({ flow, movableCount }: { flow: AlmFlow; movableCount: number }) {
  const steps = buildSteps(flow, movableCount)

  return (
    <aside className="wizard">
      <Text weight="semibold" size={300} block style={{ marginBottom: 'var(--space-xs)' }}>
        Progress
      </Text>
      <ol className="wizard-list">
        {steps.map((s, i) => (
          <li key={s.key} className={`wizard-step wizard-step-${s.state}`}>
            <span className="wizard-step-marker">
              <StepIcon state={s.state} index={i} />
            </span>
            <span className="wizard-step-body">
              <span className="wizard-step-title">{s.title}</span>
              <span className="wizard-step-detail">{s.detail}</span>
            </span>
          </li>
        ))}
      </ol>
    </aside>
  )
}
