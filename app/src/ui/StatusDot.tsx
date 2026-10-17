import type { HTMLAttributes, ReactNode } from 'react'
import { cx } from './utils'

export type StatusKind = 'new' | 'changed' | 'extra' | 'same' | 'blocked' | 'ready' | 'running' | 'failed' | 'skipped' | 'done'

/** fill = solid dot, ring = hollow 2px ring, dash = short bar, spin = rotating open ring. */
export type StatusShape = 'fill' | 'ring' | 'dash' | 'spin'

export interface StatusStyle {
  /** Default label (sentence case). */
  label: string
  /** What the kind means, for tooltips and legends. */
  description: string
  /** Token that paints the mark, without the leading `--`. */
  token: string
  /** CSS value, `var(--token)`, for reuse in charts and legends. */
  color: string
  shape: StatusShape
}

const s = (label: string, description: string, token: string, shape: StatusShape): StatusStyle => ({
  label,
  description,
  token,
  color: `var(--${token})`,
  shape,
})

/**
 * Dot colour and shape per kind. Within each family the marks differ in lightness or shape as well
 * as hue (relative luminance in brackets; the brand tokens are the same in both themes):
 *
 * Compare: new = fill brand-teal (0.18) · changed = fill brand-yellow (0.53) ·
 *          extra = ring brand-purple (0.14) · same = dash text-secondary
 * Run:     done = fill brand-teal (0.18) · failed = fill negative-on-lite (0.07 light / 0.52 dark) ·
 *          ready = ring action-active (0.17) · blocked = ring brand-orange (0.38) ·
 *          running = spin action-active · skipped = dash text-secondary
 *
 * The label is always shown (or given to assistive tech); the mark never carries meaning alone.
 */
export const STATUS_STYLES: Record<StatusKind, StatusStyle> = {
  new: s('New', 'Exists only in the source; will be created in the target.', 'brand-teal', 'fill'),
  changed: s('Changed', 'Exists in both, with differences; will be updated.', 'brand-yellow', 'fill'),
  extra: s('Only in target', 'Exists only in the target; left as it is.', 'brand-purple', 'ring'),
  same: s('Same', 'Identical in source and target; nothing to do.', 'text-secondary', 'dash'),
  ready: s('Ready', 'Checks passed; ready to run.', 'action-active', 'ring'),
  running: s('Running', 'In progress.', 'action-active', 'spin'),
  done: s('Done', 'Completed successfully.', 'brand-teal', 'fill'),
  failed: s('Failed', 'Did not complete; see the error.', 'negative-on-lite', 'fill'),
  blocked: s('Blocked', 'Cannot run until a dependency or input is resolved.', 'brand-orange', 'ring'),
  skipped: s('Skipped', 'Not run, by choice or because nothing changed.', 'text-secondary', 'dash'),
}

export const STATUS_KINDS = Object.keys(STATUS_STYLES) as StatusKind[]

export interface StatusDotProps extends HTMLAttributes<HTMLSpanElement> {
  kind: StatusKind
  /** Accessible name. Omit when a visible label sits next to the dot (the dot is then hidden). */
  label?: string
}

/** 8px status mark. Decorative unless `label` is given. */
export function StatusDot({ kind, label, className, ...rest }: StatusDotProps) {
  const st = STATUS_STYLES[kind]
  return (
    <span
      role={label ? 'img' : undefined}
      aria-label={label}
      aria-hidden={label ? undefined : true}
      className={cx('ui-status-dot', `ui-status-dot--${st.shape}`, st.shape === 'spin' && 'ui-motion-essential', className)}
      style={{ ['--ui-status-color' as string]: st.color }}
      {...rest}
    />
  )
}

export interface StatusLabelProps extends HTMLAttributes<HTMLSpanElement> {
  kind: StatusKind
  /** Overrides the default label text. */
  children?: ReactNode
  /** Label in text-secondary instead of text-primary. */
  muted?: boolean
  /** 14px (default) or 16px. */
  size?: 'sm' | 'md'
}

/** Dot plus text label. The text is always text-primary or text-secondary, never the status colour. */
export function StatusLabel({ kind, children, muted, size = 'sm', className, ...rest }: StatusLabelProps) {
  return (
    <span className={cx('ui-status-label', muted && 'ui-status-label--muted', size === 'md' && 'ui-status-label--md', className)} {...rest}>
      <StatusDot kind={kind} />
      <span>{children ?? STATUS_STYLES[kind].label}</span>
    </span>
  )
}
