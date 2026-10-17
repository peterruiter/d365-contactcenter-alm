import { forwardRef, useEffect, useId, useRef, type InputHTMLAttributes, type ReactNode } from 'react'
import { cx, setRefs } from './utils'

export interface CheckboxProps extends Omit<InputHTMLAttributes<HTMLInputElement>, 'type'> {
  /** Visible, clickable label. Pass `hideLabel` for table-row checkboxes that still need a name. */
  label?: ReactNode
  hideLabel?: boolean
  /** Helper text under the label. */
  hint?: ReactNode
  /** Mixed state for a parent of partially selected children: aria-checked="mixed" and a dash. */
  indeterminate?: boolean
}

/** The Zodiak checkbox: 17px box, 2px text-primary border, 3px radius. The real input carries the state. */
export const Checkbox = forwardRef<HTMLInputElement, CheckboxProps>(function Checkbox(
  { label, hideLabel, hint, indeterminate = false, id, className, disabled, 'aria-describedby': describedBy, ...rest },
  ref,
) {
  const autoId = useId()
  const inputId = id ?? autoId
  const hintId = hint ? `${inputId}-hint` : undefined
  const inner = useRef<HTMLInputElement | null>(null)

  useEffect(() => {
    if (inner.current) inner.current.indeterminate = indeterminate
  }, [indeterminate])

  return (
    <div className={cx('cgz-check', disabled && 'cgz-check--disabled', className)}>
      <input
        ref={(node) => setRefs(node, inner, ref)}
        id={inputId}
        type="checkbox"
        className="cgz-check__input"
        disabled={disabled}
        aria-checked={indeterminate ? 'mixed' : undefined}
        aria-describedby={[describedBy, hintId].filter(Boolean).join(' ') || undefined}
        {...rest}
      />
      <label htmlFor={inputId} className={cx('cgz-check__label', hideLabel && 'cgz-check__label--bare')}>
        <span className="cgz-check__box" aria-hidden="true" />
        <span className={cx('cgz-check__text', hideLabel && 'ui-visually-hidden')}>{label}</span>
      </label>
      {hint && (
        <span id={hintId} className="cgz-check__hint">
          {hint}
        </span>
      )}
    </div>
  )
})
