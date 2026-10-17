import { useId, type HTMLAttributes, type ReactNode } from 'react'
import { cx } from './utils'

export interface PanelProps extends Omit<HTMLAttributes<HTMLElement>, 'title'> {
  /** Panel heading, set at the h4 size. */
  title?: ReactNode
  /** Heading element. Default `h2` (pick by document level, not by size). */
  titleAs?: 'h2' | 'h3' | 'h4'
  /** Short text under the title, in text-secondary. */
  description?: ReactNode
  /** Right-hand slot in the header row (buttons, filters). */
  actions?: ReactNode
  /** Removes the inner padding (e.g. for an edge-to-edge table). The header keeps its inset. */
  flush?: boolean
}

/** Section container: surface-primary-neutral-lite, 1px border-primary, radius-md, no shadow. */
export function Panel({ title, titleAs: TitleTag = 'h2', description, actions, flush, className, children, ...rest }: PanelProps) {
  const titleId = useId()
  const hasHeader = !!(title || description || actions)
  return (
    <section
      className={cx('ui-panel', flush && 'ui-panel--flush', className)}
      aria-labelledby={title ? titleId : undefined}
      {...rest}
    >
      {hasHeader && (
        <div className="ui-panel__header">
          <div className="ui-panel__heading">
            {title && (
              <TitleTag id={titleId} className="ui-panel__title t-h4">
                {title}
              </TitleTag>
            )}
            {description && <p className="ui-panel__description">{description}</p>}
          </div>
          {actions && <div className="ui-panel__actions">{actions}</div>}
        </div>
      )}
      {children !== undefined && children !== null && <div className="ui-panel__body">{children}</div>}
    </section>
  )
}
