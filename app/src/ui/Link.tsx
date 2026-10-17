import { forwardRef, type AnchorHTMLAttributes } from 'react'
import { cx } from './utils'

export interface LinkProps extends AnchorHTMLAttributes<HTMLAnchorElement> {
  /** `default` sweeps border-secondary, `highlight` the peacock highlight, `inverse` is for heavy blues. */
  variant?: 'default' | 'highlight' | 'inverse'
  /** Persistent underline. Set it for links inside running copy. */
  underline?: boolean
}

/** Text link with the Capgemini baseline sweep on hover. */
export const Link = forwardRef<HTMLAnchorElement, LinkProps>(function Link(
  { variant = 'default', underline, className, target, rel, ...rest },
  ref,
) {
  return (
    <a
      ref={ref}
      target={target}
      rel={rel ?? (target === '_blank' ? 'noopener noreferrer' : undefined)}
      className={cx(
        'cgz-link',
        variant !== 'default' && `cgz-link--${variant}`,
        underline && 'cgz-link--underline',
        variant === 'inverse' && 'ui-on-heavy',
        className,
      )}
      {...rest}
    />
  )
})
