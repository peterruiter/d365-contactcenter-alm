import { forwardRef, useId, type ReactNode, type TextareaHTMLAttributes } from 'react'
import { FieldShell, fieldIds } from './Field'
import { cx } from './utils'

export interface TextareaProps extends TextareaHTMLAttributes<HTMLTextAreaElement> {
  label?: ReactNode
  hideLabel?: boolean
  hint?: ReactNode
  error?: ReactNode
  fieldClassName?: string
}

/** Multi-line text field with the Input geometry; resizes vertically. */
export const Textarea = forwardRef<HTMLTextAreaElement, TextareaProps>(function Textarea(
  { label, hideLabel, hint, error, id, rows = 4, className, fieldClassName, 'aria-describedby': describedBy, ...rest },
  ref,
) {
  const autoId = useId()
  const inputId = id ?? autoId
  const ids = fieldIds(inputId, hint, error, describedBy)
  return (
    <FieldShell id={inputId} label={label} hideLabel={hideLabel} hint={hint} error={error} ids={ids} className={fieldClassName}>
      <textarea
        ref={ref}
        id={inputId}
        rows={rows}
        className={cx('cgz-input', 'cgz-textarea', error ? 'cgz-input--invalid' : null, className)}
        aria-invalid={error ? true : undefined}
        aria-describedby={ids.describedBy}
        {...rest}
      />
    </FieldShell>
  )
})
