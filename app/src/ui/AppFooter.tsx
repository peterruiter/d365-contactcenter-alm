import type { HTMLAttributes, ReactNode } from 'react'
import { cx } from './utils'

export interface AppFooterProps extends HTMLAttributes<HTMLElement> {
  /** Left slot (wraps above `right` on narrow screens). */
  left?: ReactNode
  /** Right slot. */
  right?: ReactNode
}

/** Slim footer on page-background with a border-primary top rule; t-body-small in text-secondary. */
export function AppFooter({ left, right, className, children, ...rest }: AppFooterProps) {
  return (
    <footer className={cx('ui-app-footer', className)} {...rest}>
      <div className="ui-app-footer__left">{left ?? children}</div>
      {right && <div className="ui-app-footer__right">{right}</div>}
    </footer>
  )
}
