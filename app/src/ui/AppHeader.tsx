import type { HTMLAttributes, ReactNode } from 'react'
import { CapgeminiLogo } from './CapgeminiLogo'
import { cx } from './utils'

export interface AppHeaderProps extends HTMLAttributes<HTMLElement> {
  productName: ReactNode
  subtitle?: ReactNode
  /** Navigation row under the title bar, e.g. `<Tabs tone="heavy" …/>`. */
  nav?: ReactNode
  /** Accessible name for the nav landmark. Default "Main". */
  navLabel?: string
  /** Right-hand slot: heavy-tone buttons, ThemeToggle tone="heavy", user info. */
  actions?: ReactNode
  /** Where the logo links to (optional). */
  logoHref?: string
}

/**
 * Full-width band on surface-ink-heavy: white Capgemini lockup at its 120px minimum width with
 * spade-height clear space, a divider, the product name in Light 300, optional subtitle, nav slot
 * and actions slot. Everything on it uses text-always-white and the heavy-tone tokens.
 */
export function AppHeader({ productName, subtitle, nav, navLabel = 'Main', actions, logoHref, className, ...rest }: AppHeaderProps) {
  const logo = <CapgeminiLogo ink="white" className="ui-app-header__logo" />
  return (
    <header className={cx('ui-app-header', 'ui-on-heavy', className)} {...rest}>
      <div className="ui-app-header__bar">
        <div className="ui-app-header__brand">
          {logoHref ? (
            <a href={logoHref} className="ui-app-header__logo-link">
              {logo}
            </a>
          ) : (
            logo
          )}
          <span className="ui-app-header__divider" aria-hidden="true" />
          <div className="ui-app-header__titles">
            <span className="ui-app-header__product">{productName}</span>
            {subtitle && <span className="ui-app-header__subtitle">{subtitle}</span>}
          </div>
        </div>
        {actions && <div className="ui-app-header__actions">{actions}</div>}
      </div>
      {nav && (
        <nav className="ui-app-header__nav" aria-label={navLabel}>
          {nav}
        </nav>
      )}
    </header>
  )
}
