import type { HTMLAttributes, ReactNode } from 'react'
import { DocumentSearchRegular } from '@fluentui/react-icons'
import { cx } from './utils'

export interface EmptyStateProps extends Omit<HTMLAttributes<HTMLDivElement>, 'title'> {
  /** 24px icon. Default: document search. */
  icon?: ReactNode
  title: ReactNode
  /** Heading element. Default `h3`. */
  titleAs?: 'h2' | 'h3' | 'h4'
  /** Say what is missing and what to do next. */
  children?: ReactNode
  /** One action (Button or Link). */
  action?: ReactNode
}

/** Centered placeholder for an empty list or result. */
export function EmptyState({ icon, title, titleAs: TitleTag = 'h3', children, action, className, ...rest }: EmptyStateProps) {
  return (
    <div className={cx('ui-empty', className)} {...rest}>
      <span className="ui-empty__icon" aria-hidden="true">
        {icon ?? <DocumentSearchRegular fontSize={24} />}
      </span>
      <TitleTag className="ui-empty__title t-h4">{title}</TitleTag>
      {children && <div className="ui-empty__text">{children}</div>}
      {action && <div className="ui-empty__action">{action}</div>}
    </div>
  )
}
