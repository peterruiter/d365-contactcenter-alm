import type { HTMLAttributes, ReactNode } from 'react'
import { cx } from './utils'

export interface KeyValueItem {
  /** Stable key; defaults to the index. */
  id?: string
  label: ReactNode
  value: ReactNode
}

export interface KeyValueProps extends HTMLAttributes<HTMLDListElement> {
  items: KeyValueItem[]
  /** 14px values instead of 16px body. */
  compact?: boolean
  /** Stack label over value at every width (default: two columns, stacking below 480px of container). */
  stacked?: boolean
}

/** Definition list in two columns; labels in text-secondary. */
export function KeyValue({ items, compact, stacked, className, ...rest }: KeyValueProps) {
  return (
    <dl className={cx('ui-kv', compact && 'ui-kv--compact', stacked && 'ui-kv--stacked', className)} {...rest}>
      {items.map((item, i) => (
        <div key={item.id ?? i} className="ui-kv__row">
          <dt className="ui-kv__label">{item.label}</dt>
          <dd className="ui-kv__value">{item.value}</dd>
        </div>
      ))}
    </dl>
  )
}
