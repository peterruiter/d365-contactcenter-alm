import type { ReactNode } from 'react'
import { cx } from './utils'

export interface FieldIds {
  hintId?: string
  errorId?: string
  describedBy?: string
}

/** Builds the aria-describedby chain for a field. Hint is hidden while an error shows. */
export function fieldIds(baseId: string, hint: ReactNode, error: ReactNode, extra?: string): FieldIds {
  const hintId = hint && !error ? `${baseId}-hint` : undefined
  const errorId = error ? `${baseId}-error` : undefined
  const describedBy = [extra, errorId, hintId].filter(Boolean).join(' ') || undefined
  return { hintId, errorId, describedBy }
}

interface FieldShellProps {
  id: string
  label?: ReactNode
  hideLabel?: boolean
  hint?: ReactNode
  error?: ReactNode
  ids: FieldIds
  className?: string
  children: ReactNode
}

/** Label above, control, then hint or error below. Shared by Input, Select, Textarea, SearchInput. */
export function FieldShell({ id, label, hideLabel, hint, error, ids, className, children }: FieldShellProps) {
  return (
    <div className={cx('cgz-field', className)}>
      {label !== undefined && label !== null && (
        <label htmlFor={id} className={cx('cgz-field__label', hideLabel && 'ui-visually-hidden')}>
          {label}
        </label>
      )}
      {children}
      {ids.errorId ? (
        <span id={ids.errorId} className="cgz-field__error">
          {error}
        </span>
      ) : ids.hintId ? (
        <span id={ids.hintId} className="cgz-field__hint">
          {hint}
        </span>
      ) : null}
    </div>
  )
}
