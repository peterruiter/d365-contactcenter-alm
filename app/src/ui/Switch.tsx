import { forwardRef, useId, type ButtonHTMLAttributes, type ReactNode } from 'react'
import { cx, type Tone } from './utils'

export interface SwitchProps extends Omit<ButtonHTMLAttributes<HTMLButtonElement>, 'onChange' | 'role'> {
  checked: boolean
  onChange: (checked: boolean) => void
  /** Visible label (clicking it toggles too). */
  label: ReactNode
  /** Keep the label for assistive tech only. */
  hideLabel?: boolean
  /** Label before (default) or after the track. */
  labelPosition?: 'start' | 'end'
  /** `heavy` on the heavy blue surfaces. Default `lite`. */
  tone?: Tone
}

/** On/off toggle that applies immediately. role="switch", radius-full track, the thumb slides. */
export const Switch = forwardRef<HTMLButtonElement, SwitchProps>(function Switch(
  { checked, onChange, label, hideLabel, labelPosition = 'start', tone = 'lite', id, className, disabled, ...rest },
  ref,
) {
  const autoId = useId()
  const switchId = id ?? autoId
  const labelId = `${switchId}-label`
  const labelEl = (
    <span id={labelId} className={cx('ui-switch__label', hideLabel && 'ui-visually-hidden')} onClick={() => !disabled && onChange(!checked)}>
      {label}
    </span>
  )
  return (
    <span className={cx('ui-switch', `ui-switch--${tone}`, disabled && 'ui-switch--disabled', tone === 'heavy' && 'ui-on-heavy', className)}>
      {labelPosition === 'start' && labelEl}
      <button
        ref={ref}
        id={switchId}
        type="button"
        role="switch"
        aria-checked={checked}
        aria-labelledby={labelId}
        disabled={disabled}
        className="ui-switch__track"
        onClick={() => onChange(!checked)}
        {...rest}
      >
        <span className="ui-switch__thumb" aria-hidden="true" />
      </button>
      {labelPosition === 'end' && labelEl}
    </span>
  )
})
