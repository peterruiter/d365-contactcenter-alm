import type { HTMLAttributes } from 'react'
import { cx, type Tone } from './utils'

export interface SpinnerProps extends HTMLAttributes<HTMLSpanElement> {
  /** `sm` is 16px, `md` 24px. Default `md`. */
  size?: 'sm' | 'md'
  /** Accessible name. Default "Loading". Ignored when `decorative`. */
  label?: string
  /** `heavy` on the heavy blue surfaces. Default `lite`. */
  tone?: Tone
  /** Hide from assistive tech (use when the surrounding control already says it is busy). */
  decorative?: boolean
  /** Paint with the current text colour instead of action-active (used inside buttons). */
  inherit?: boolean
}

/** A rotating ring: border-secondary track, action-active arc. */
export function Spinner({ size = 'md', label = 'Loading', tone = 'lite', decorative, inherit, className, ...rest }: SpinnerProps) {
  return (
    <span
      role={decorative ? undefined : 'img'}
      aria-label={decorative ? undefined : label}
      aria-hidden={decorative ? true : undefined}
      className={cx(
        'ui-spinner',
        'ui-motion-essential',
        `ui-spinner--${size}`,
        tone === 'heavy' && 'ui-spinner--heavy',
        inherit && 'ui-spinner--inherit',
        className,
      )}
      {...rest}
    />
  )
}
