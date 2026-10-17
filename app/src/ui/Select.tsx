import { forwardRef, useId, type ReactNode, type SelectHTMLAttributes } from 'react'
import { ChevronDownRegular } from '@fluentui/react-icons'
import { FieldShell, fieldIds } from './Field'
import { cx } from './utils'

export type SelectOption = string | { value: string; label: string; disabled?: boolean }

export interface SelectProps extends Omit<SelectHTMLAttributes<HTMLSelectElement>, 'size'> {
  label?: ReactNode
  hideLabel?: boolean
  hint?: ReactNode
  error?: ReactNode
  /** `md` is 48px, `lg` 58px. Default `md`. */
  size?: 'md' | 'lg'
  /** Strings or `{ value, label }` pairs. Children are rendered after these. */
  options?: SelectOption[]
  /** Labelled empty first option, e.g. "Select an environment". */
  placeholder?: string
  fieldClassName?: string
}

/** Native select with the Input geometry and an inline chevron. */
export const Select = forwardRef<HTMLSelectElement, SelectProps>(function Select(
  {
    label,
    hideLabel,
    hint,
    error,
    size = 'md',
    options,
    placeholder,
    id,
    className,
    fieldClassName,
    children,
    multiple,
    'aria-describedby': describedBy,
    ...rest
  },
  ref,
) {
  const autoId = useId()
  const selectId = id ?? autoId
  const ids = fieldIds(selectId, hint, error, describedBy)
  return (
    <FieldShell id={selectId} label={label} hideLabel={hideLabel} hint={hint} error={error} ids={ids} className={fieldClassName}>
      <div className={cx('cgz-select-wrap', multiple && 'cgz-select-wrap--multiple')}>
        <select
          ref={ref}
          id={selectId}
          multiple={multiple}
          className={cx('cgz-select', size === 'lg' && 'cgz-select--lg', error ? 'cgz-select--invalid' : null, className)}
          aria-invalid={error ? true : undefined}
          aria-describedby={ids.describedBy}
          {...rest}
        >
          {placeholder !== undefined && (
            <option value="" disabled={rest.required}>
              {placeholder}
            </option>
          )}
          {options?.map((o) =>
            typeof o === 'string' ? (
              <option key={o} value={o}>
                {o}
              </option>
            ) : (
              <option key={o.value} value={o.value} disabled={o.disabled}>
                {o.label}
              </option>
            ),
          )}
          {children}
        </select>
        {!multiple && (
          <span className="cgz-select__chevron" aria-hidden="true">
            <ChevronDownRegular fontSize={20} />
          </span>
        )}
      </div>
    </FieldShell>
  )
})
