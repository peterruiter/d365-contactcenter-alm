import type { ReactNode } from 'react'
import { cx } from './utils'

export interface FilterChip {
  id: string
  label: string
  /** Count shown after the label. */
  count?: number
  disabled?: boolean
}

export interface FilterChipsProps {
  items: FilterChip[]
  /** Pressed chip ids. */
  selected: string[]
  onChange: (selected: string[]) => void
  /** Accessible name of the group, e.g. "Filter by status". */
  'aria-label': string
  /** Only one chip pressed at a time (pressing it again clears). Default false. */
  single?: boolean
  /** Optional leading content inside the group (e.g. a visible "Show" label). */
  prefix?: ReactNode
  className?: string
}

/**
 * Row of toggle chips in the Tag look. Pressed: filled text-link pill with text-inverse.
 * Unpressed: quiet outline. Each chip is a button with aria-pressed.
 */
export function FilterChips({ items, selected, onChange, single, prefix, className, 'aria-label': ariaLabel }: FilterChipsProps) {
  const toggle = (id: string) => {
    const on = selected.includes(id)
    if (single) onChange(on ? [] : [id])
    else onChange(on ? selected.filter((s) => s !== id) : [...selected, id])
  }
  return (
    <div role="group" aria-label={ariaLabel} className={cx('ui-chips', className)}>
      {prefix}
      {items.map((chip) => {
        const pressed = selected.includes(chip.id)
        return (
          <button
            key={chip.id}
            type="button"
            aria-pressed={pressed}
            disabled={chip.disabled}
            className={cx('ui-chip', pressed && 'ui-chip--pressed')}
            onClick={() => toggle(chip.id)}
          >
            <span>{chip.label}</span>
            {chip.count !== undefined && <span className="ui-chip__count">{chip.count}</span>}
          </button>
        )
      })}
    </div>
  )
}
