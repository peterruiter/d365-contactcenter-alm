import type { CSSProperties, HTMLAttributes } from 'react'
import { cx } from './utils'

export interface SkeletonProps extends HTMLAttributes<HTMLSpanElement> {
  /** `text` is a 1em line, `block` a rectangle, `circle` a round avatar/marker. Default `text`. */
  variant?: 'text' | 'block' | 'circle'
  width?: CSSProperties['width']
  height?: CSSProperties['height']
}

/**
 * Loading placeholder: border-secondary fill, a gentle opacity pulse (no shimmer), still under
 * prefers-reduced-motion. Decorative; set aria-busy="true" on the region that is loading.
 */
export function Skeleton({ variant = 'text', width, height, className, style, ...rest }: SkeletonProps) {
  return (
    <span
      aria-hidden="true"
      className={cx('ui-skeleton', `ui-skeleton--${variant}`, className)}
      style={{ width, height, ...style }}
      {...rest}
    />
  )
}

export interface SkeletonTextProps {
  /** Number of lines. Default 3; the last is shorter. */
  lines?: number
  className?: string
}

export function SkeletonText({ lines = 3, className }: SkeletonTextProps) {
  return (
    <span className={cx('ui-skeleton-text', className)} aria-hidden="true">
      {Array.from({ length: lines }, (_, i) => (
        <Skeleton key={i} width={i === lines - 1 && lines > 1 ? '60%' : '100%'} />
      ))}
    </span>
  )
}
