import { useId, type HTMLAttributes, type ReactNode } from 'react'
import { cx } from './utils'

export interface ProgressBarProps extends Omit<HTMLAttributes<HTMLDivElement>, 'children'> {
  /** Current value. Omit for an indeterminate bar. */
  value?: number
  /** Default 100. */
  max?: number
  /** Visible label above the bar; also its accessible name. Otherwise pass `aria-label`. */
  label?: ReactNode
  /** Show the percentage at the end of the label row. */
  showValue?: boolean
  /** Text for assistive tech instead of the percentage, e.g. "3 of 12 items". */
  valueText?: string
}

/** action-active fill on a border-secondary track. Indeterminate when `value` is undefined. */
export function ProgressBar({ value, max = 100, label, showValue, valueText, className, ...rest }: ProgressBarProps) {
  const labelId = useId()
  const indeterminate = value === undefined
  const pct = indeterminate ? 0 : Math.max(0, Math.min(100, (value / (max || 1)) * 100))
  return (
    <div className={cx('ui-progress', indeterminate && 'ui-progress--indeterminate', className)}>
      {(label || (showValue && !indeterminate)) && (
        <div className="ui-progress__meta">
          {label && (
            <span id={labelId} className="ui-progress__label">
              {label}
            </span>
          )}
          {showValue && !indeterminate && <span className="ui-progress__value">{Math.round(pct)}%</span>}
        </div>
      )}
      <div
        role="progressbar"
        aria-labelledby={label ? labelId : undefined}
        aria-valuemin={indeterminate ? undefined : 0}
        aria-valuemax={indeterminate ? undefined : max}
        aria-valuenow={indeterminate ? undefined : value}
        aria-valuetext={valueText}
        className="ui-progress__track"
        {...rest}
      >
        <span
          className={cx('ui-progress__fill', indeterminate && 'ui-motion-essential')}
          style={indeterminate ? undefined : { width: `${pct}%` }}
        />
      </div>
    </div>
  )
}
