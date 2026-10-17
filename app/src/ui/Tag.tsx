import type { HTMLAttributes, MouseEvent } from 'react'
import { DismissRegular } from '@fluentui/react-icons'
import { cx } from './utils'

export interface TagProps extends HTMLAttributes<HTMLSpanElement> {
  /** Outline instead of the filled text-link pill. Use for read-only labels. */
  quiet?: boolean
  /** Shows the remove control and fires on click. */
  onRemove?: (event: MouseEvent<HTMLButtonElement>) => void
  /** Accessible name for the remove control, e.g. "Remove Cloud filter". Default "Remove". */
  removeLabel?: string
}

/** Filter chip / label pill. The fill is fixed to text-link; category goes in the label, not the colour. */
export function Tag({ quiet, onRemove, removeLabel = 'Remove', className, children, ...rest }: TagProps) {
  return (
    <span className={cx('cgz-tag', quiet && 'cgz-tag--quiet', onRemove && 'cgz-tag--removable', className)} {...rest}>
      <span className="cgz-tag__label">{children}</span>
      {onRemove && (
        <button type="button" className="cgz-tag__remove" aria-label={removeLabel} title={removeLabel} onClick={onRemove}>
          <DismissRegular fontSize={16} aria-hidden="true" />
        </button>
      )}
    </span>
  )
}
