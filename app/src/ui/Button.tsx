import { forwardRef, type AnchorHTMLAttributes, type ButtonHTMLAttributes, type ReactNode, type Ref } from 'react'
import { ArrowRightRegular } from '@fluentui/react-icons'
import { Spinner } from './Spinner'
import { cx, type Tone } from './utils'

export interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  /** Which action token family to paint with. Default `primary`; one primary per view. */
  variant?: 'primary' | 'secondary'
  /** The ground, not the theme: `heavy` on the heavy blue surfaces. Default `lite`. */
  tone?: Tone
  /** `md` is 48px, `sm` 38px (toolbars, filters). Default `md`. */
  size?: 'md' | 'sm'
  /** Trailing arrow. Use only when the button navigates, never on submit. */
  icon?: boolean
  /** Icon before the label (16px box). */
  leadingIcon?: ReactNode
  /** Shows a spinner, sets aria-busy and disables the control. */
  busy?: boolean
  /** Renders an anchor with the same styling. */
  href?: string
  target?: AnchorHTMLAttributes<HTMLAnchorElement>['target']
  rel?: AnchorHTMLAttributes<HTMLAnchorElement>['rel']
  download?: AnchorHTMLAttributes<HTMLAnchorElement>['download']
}

/** Capgemini button: an outline pill that fills on hover. Only colours change on hover. */
export const Button = forwardRef<HTMLButtonElement | HTMLAnchorElement, ButtonProps>(function Button(
  {
    variant = 'primary',
    tone = 'lite',
    size = 'md',
    icon,
    leadingIcon,
    busy,
    href,
    target,
    rel,
    download,
    disabled,
    className,
    children,
    type,
    ...rest
  },
  ref,
) {
  const classes = cx(
    'cgz-btn',
    `cgz-btn--${variant}`,
    `cgz-btn--${tone}`,
    size === 'sm' && 'cgz-btn--sm',
    busy && 'cgz-btn--busy',
    tone === 'heavy' && 'ui-on-heavy',
    className,
  )
  const inactive = disabled || busy
  const content = (
    <>
      {busy ? (
        <span className="cgz-btn__lead">
          <Spinner size="sm" decorative inherit />
        </span>
      ) : leadingIcon ? (
        <span className="cgz-btn__lead" aria-hidden="true">
          {leadingIcon}
        </span>
      ) : null}
      <span className="cgz-btn__label">{children}</span>
      {icon && (
        <span className="cgz-btn__icon" aria-hidden="true">
          <ArrowRightRegular fontSize={16} />
        </span>
      )}
    </>
  )

  if (href !== undefined) {
    const anchorRest = rest as unknown as AnchorHTMLAttributes<HTMLAnchorElement>
    return (
      <a
        ref={ref as Ref<HTMLAnchorElement>}
        className={classes}
        href={inactive ? undefined : href}
        target={target}
        rel={rel ?? (target === '_blank' ? 'noopener noreferrer' : undefined)}
        download={download}
        aria-disabled={inactive || undefined}
        aria-busy={busy || undefined}
        {...anchorRest}
      >
        {content}
      </a>
    )
  }

  return (
    <button
      ref={ref as Ref<HTMLButtonElement>}
      type={type ?? 'button'}
      className={classes}
      disabled={inactive}
      aria-busy={busy || undefined}
      {...rest}
    >
      {content}
    </button>
  )
})
