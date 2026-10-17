import { forwardRef, type ButtonHTMLAttributes, type ReactNode } from 'react'
import { cx, type Tone } from './utils'

export interface IconButtonProps extends Omit<ButtonHTMLAttributes<HTMLButtonElement>, 'aria-label' | 'title'> {
  /** Required accessible name; also shown as the native tooltip. */
  label: string
  /** The icon (a 20px Fluent `*Regular` icon). */
  icon: ReactNode
  /** Token family, as on Button. Default `primary`. */
  variant?: 'primary' | 'secondary'
  /** Ground: `heavy` on the heavy blue surfaces. Default `lite`. */
  tone?: Tone
  /** `md` is 40px, `sm` 32px. Default `md`. */
  size?: 'md' | 'sm'
  /** No outline at rest; a quiet fill on hover. For dismiss controls and dense toolbars. */
  quiet?: boolean
  /** Toggle state; sets aria-pressed and the filled look. */
  pressed?: boolean
}

/** Round icon-only button (radius-full). Outline at rest, fills on hover like Button. */
export const IconButton = forwardRef<HTMLButtonElement, IconButtonProps>(function IconButton(
  { label, icon, variant = 'primary', tone = 'lite', size = 'md', quiet, pressed, className, type, ...rest },
  ref,
) {
  return (
    <button
      ref={ref}
      type={type ?? 'button'}
      aria-label={label}
      title={label}
      aria-pressed={pressed}
      className={cx(
        'ui-icon-btn',
        `ui-icon-btn--${variant}`,
        `ui-icon-btn--${tone}`,
        `ui-icon-btn--${size}`,
        quiet && 'ui-icon-btn--quiet',
        pressed && 'ui-icon-btn--pressed',
        tone === 'heavy' && 'ui-on-heavy',
        className,
      )}
      {...rest}
    >
      <span className="ui-icon-btn__icon" aria-hidden="true">
        {icon}
      </span>
    </button>
  )
})
