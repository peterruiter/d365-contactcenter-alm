import type { HTMLAttributes, ReactNode } from 'react'
import { CheckmarkCircleRegular, DismissRegular, ErrorCircleRegular, InfoRegular, WarningRegular } from '@fluentui/react-icons'
import { IconButton } from './IconButton'
import { cx } from './utils'

export type NoticeTone = 'info' | 'success' | 'warning' | 'error'

export interface NoticeProps extends Omit<HTMLAttributes<HTMLDivElement>, 'title'> {
  tone?: NoticeTone
  title?: ReactNode
  children?: ReactNode
  /** Actions under the message (small Buttons or Links). */
  actions?: ReactNode
  /** Shows a dismiss control. */
  onDismiss?: () => void
  /** Default "Dismiss". */
  dismissLabel?: string
  /**
   * Live-region role. Default: `alert` for error, `status` otherwise. Pass `none` for a notice that
   * is part of the page on load and should not be announced.
   */
  live?: 'auto' | 'none'
}

const ICONS: Record<NoticeTone, ReactNode> = {
  info: <InfoRegular fontSize={20} />,
  success: <CheckmarkCircleRegular fontSize={20} />,
  warning: <WarningRegular fontSize={20} />,
  error: <ErrorCircleRegular fontSize={20} />,
}

const TONE_WORD: Record<NoticeTone, string> = { info: 'Information', success: 'Success', warning: 'Warning', error: 'Error' }

/** Inline message. Always icon plus text, never colour alone. */
export function Notice({
  tone = 'info',
  title,
  children,
  actions,
  onDismiss,
  dismissLabel = 'Dismiss',
  live = 'auto',
  className,
  ...rest
}: NoticeProps) {
  const role = live === 'none' ? undefined : tone === 'error' ? 'alert' : 'status'
  return (
    <div role={role} className={cx('ui-notice', `ui-notice--${tone}`, className)} {...rest}>
      <span className="ui-notice__icon" aria-hidden="true">
        {ICONS[tone]}
      </span>
      <div className="ui-notice__content">
        <span className="ui-visually-hidden">{TONE_WORD[tone]}: </span>
        {title && <p className="ui-notice__title">{title}</p>}
        {children && <div className="ui-notice__body">{children}</div>}
        {actions && <div className="ui-notice__actions">{actions}</div>}
      </div>
      {onDismiss && (
        <IconButton
          className="ui-notice__dismiss"
          quiet
          size="sm"
          label={dismissLabel}
          icon={<DismissRegular fontSize={20} />}
          onClick={onDismiss}
        />
      )}
    </div>
  )
}
