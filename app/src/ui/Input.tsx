import { forwardRef, useId, type InputHTMLAttributes, type ReactNode } from 'react'
import { FieldShell, fieldIds } from './Field'
import { cx } from './utils'

export interface InputProps extends Omit<InputHTMLAttributes<HTMLInputElement>, 'size'> {
  /** Visible label, bound to the input. Do not use the placeholder as a label. */
  label?: ReactNode
  /** Keep the label for assistive tech only (use sparingly, e.g. in a toolbar). */
  hideLabel?: boolean
  /** Helper text under the field in text-secondary. Hidden while `error` is set. */
  hint?: ReactNode
  /** Error text in negative-on-lite; also sets aria-invalid and the negative border. */
  error?: ReactNode
  /** `md` is 48px, `lg` 58px. Default `md`. */
  size?: 'md' | 'lg'
  /** Class for the outer field wrapper. */
  fieldClassName?: string
}

/** Single-line text field: 48px, radius-sm, border-primary hairline. */
export const Input = forwardRef<HTMLInputElement, InputProps>(function Input(
  { label, hideLabel, hint, error, size = 'md', id, className, fieldClassName, 'aria-describedby': describedBy, ...rest },
  ref,
) {
  const autoId = useId()
  const inputId = id ?? autoId
  const ids = fieldIds(inputId, hint, error, describedBy)
  return (
    <FieldShell id={inputId} label={label} hideLabel={hideLabel} hint={hint} error={error} ids={ids} className={fieldClassName}>
      <input
        ref={ref}
        id={inputId}
        className={cx('cgz-input', size === 'lg' && 'cgz-input--lg', error ? 'cgz-input--invalid' : null, className)}
        aria-invalid={error ? true : undefined}
        aria-describedby={ids.describedBy}
        {...rest}
      />
    </FieldShell>
  )
})
