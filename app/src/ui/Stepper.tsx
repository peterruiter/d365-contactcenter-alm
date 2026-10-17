import type { ReactNode } from 'react'
import { CheckmarkRegular, DismissRegular, WarningRegular } from '@fluentui/react-icons'
import { cx } from './utils'

export type StepState = 'done' | 'current' | 'upcoming' | 'error' | 'warning'

export interface StepItem {
  id: string
  label: string
  description?: ReactNode
  state: StepState
}

export interface StepperProps {
  steps: StepItem[]
  /** Makes reachable steps clickable. */
  onSelect?: (id: string) => void
  /** Which steps can be clicked. Default: every step that is not `upcoming`. */
  isReachable?: (step: StepItem, index: number) => boolean
  /** Accessible name for the step list. Default "Progress". */
  'aria-label'?: string
  className?: string
}

const STATE_TEXT: Record<StepState, string> = {
  done: 'completed',
  current: 'current step',
  upcoming: 'not started',
  error: 'has errors',
  warning: 'has warnings',
}

function Marker({ state, index }: { state: StepState; index: number }) {
  return (
    <span className={cx('ui-step__marker', `ui-step__marker--${state}`)} aria-hidden="true">
      {state === 'done' ? (
        <CheckmarkRegular fontSize={20} />
      ) : state === 'error' ? (
        <DismissRegular fontSize={20} />
      ) : state === 'warning' ? (
        <WarningRegular fontSize={20} />
      ) : (
        index + 1
      )}
    </span>
  )
}

/**
 * Horizontal step indicator for a guided flow. Numbers in circles, a check when done, action-active
 * fill on the current step. Below 640px of container width it collapses to "Step 2 of 4 · Label".
 */
export function Stepper({ steps, onSelect, isReachable, className, 'aria-label': ariaLabel = 'Progress' }: StepperProps) {
  const currentIndex = Math.max(
    0,
    steps.findIndex((s) => s.state === 'current'),
  )
  const current = steps[currentIndex]
  const reachable = (s: StepItem, i: number) => (isReachable ? isReachable(s, i) : s.state !== 'upcoming')

  return (
    <nav className={cx('ui-stepper', className)} aria-label={ariaLabel}>
      <ol className="ui-stepper__list">
        {steps.map((step, i) => {
          const clickable = !!onSelect && reachable(step, i) && step.state !== 'current'
          const body = (
            <>
              <Marker state={step.state} index={i} />
              <span className="ui-step__text">
                <span className="ui-step__label">{step.label}</span>
                {step.description && <span className="ui-step__description">{step.description}</span>}
                <span className="ui-visually-hidden">, {STATE_TEXT[step.state]}</span>
              </span>
            </>
          )
          return (
            <li
              key={step.id}
              className={cx('ui-step', `ui-step--${step.state}`, i < steps.length - 1 && 'ui-step--has-next')}
              aria-current={step.state === 'current' ? 'step' : undefined}
            >
              {clickable ? (
                <button type="button" className="ui-step__body ui-step__body--button" onClick={() => onSelect!(step.id)}>
                  {body}
                </button>
              ) : (
                <span className="ui-step__body">{body}</span>
              )}
              {i < steps.length - 1 && <span className="ui-step__connector" aria-hidden="true" />}
            </li>
          )
        })}
      </ol>

      {current && (
        // Shown instead of the list in narrow containers (CSS container query); the list is then display:none.
        <div className="ui-stepper__compact">
          <div className="ui-stepper__compact-text">
            <Marker state={current.state} index={currentIndex} />
            <span>
              Step {currentIndex + 1} of {steps.length} · <span className="ui-stepper__compact-label">{current.label}</span>
              <span className="ui-visually-hidden">, {STATE_TEXT[current.state]}</span>
            </span>
          </div>
          <div className="ui-stepper__segments" aria-hidden="true">
            {steps.map((s) => (
              <span key={s.id} className={cx('ui-stepper__segment', `ui-stepper__segment--${s.state}`)} />
            ))}
          </div>
        </div>
      )}
    </nav>
  )
}
