import type { HTMLAttributes } from 'react'
import { cx } from './utils'

export interface BadgeProps extends HTMLAttributes<HTMLSpanElement> {
  /** `default`: surface-cloud-lite with text-primary. `strong`: surface-azur-heavy with text-always-white. */
  tone?: 'default' | 'strong'
}

/**
 * Small count pill ("12"). The number alone is ambiguous to screen readers; give context in the
 * surrounding label or via `aria-label` (e.g. aria-label="12 changes").
 */
export function Badge({ tone = 'default', className, ...rest }: BadgeProps) {
  return <span className={cx('ui-badge', tone === 'strong' && 'ui-badge--strong', className)} {...rest} />
}
