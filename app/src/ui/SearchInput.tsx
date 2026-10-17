import { forwardRef, useId, useRef, type InputHTMLAttributes, type KeyboardEvent, type ReactNode } from 'react'
import { DismissRegular, SearchRegular } from '@fluentui/react-icons'
import { FieldShell, fieldIds } from './Field'
import { IconButton } from './IconButton'
import { cx, setRefs } from './utils'

export interface SearchInputProps extends Omit<InputHTMLAttributes<HTMLInputElement>, 'size' | 'onChange' | 'value' | 'type'> {
  value: string
  onChange: (value: string) => void
  /** Called after the clear button or Escape empties the field. */
  onClear?: () => void
  /** Required accessible name; visible unless `hideLabel`. */
  label: ReactNode
  hideLabel?: boolean
  hint?: ReactNode
  /** Default "Clear search". */
  clearLabel?: string
  /** `md` is 48px, `sm` 38px for toolbars. Default `md`. */
  size?: 'md' | 'sm'
  fieldClassName?: string
}

/** Input with a leading search icon and a clear button. Escape clears. */
export const SearchInput = forwardRef<HTMLInputElement, SearchInputProps>(function SearchInput(
  {
    value,
    onChange,
    onClear,
    label,
    hideLabel,
    hint,
    clearLabel = 'Clear search',
    size = 'md',
    id,
    className,
    fieldClassName,
    onKeyDown,
    'aria-describedby': describedBy,
    ...rest
  },
  ref,
) {
  const autoId = useId()
  const inputId = id ?? autoId
  const ids = fieldIds(inputId, hint, undefined, describedBy)
  const inner = useRef<HTMLInputElement | null>(null)

  const clear = () => {
    onChange('')
    onClear?.()
    inner.current?.focus()
  }

  return (
    <FieldShell id={inputId} label={label} hideLabel={hideLabel} hint={hint} ids={ids} className={fieldClassName}>
      <div className={cx('ui-search', size === 'sm' && 'ui-search--sm')}>
        <span className="ui-search__icon" aria-hidden="true">
          <SearchRegular fontSize={20} />
        </span>
        <input
          ref={(node) => setRefs(node, inner, ref)}
          id={inputId}
          type="search"
          value={value}
          onChange={(e) => onChange(e.target.value)}
          onKeyDown={(e: KeyboardEvent<HTMLInputElement>) => {
            onKeyDown?.(e)
            if (e.key === 'Escape' && value) {
              e.preventDefault()
              clear()
            }
          }}
          aria-describedby={ids.describedBy}
          className={cx('cgz-input', 'ui-search__input', className)}
          {...rest}
        />
        {value && (
          <IconButton
            className="ui-search__clear"
            quiet
            size="sm"
            label={clearLabel}
            icon={<DismissRegular fontSize={20} />}
            onClick={clear}
          />
        )}
      </div>
    </FieldShell>
  )
})
