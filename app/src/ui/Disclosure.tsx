import { useId, useState, type HTMLAttributes, type ReactNode } from 'react'
import { ChevronDownRegular } from '@fluentui/react-icons'
import { cx } from './utils'

/** Spread these on the button you render as the trigger. */
export interface DisclosureTriggerProps {
  id: string
  type: 'button'
  'aria-expanded': boolean
  'aria-controls': string
  onClick: () => void
}

export interface DisclosureRenderArgs {
  open: boolean
  toggle: () => void
  triggerProps: DisclosureTriggerProps
}

export interface DisclosureProps extends Omit<HTMLAttributes<HTMLDivElement>, 'children'> {
  /** Render the trigger. Spread `triggerProps` on a real `<button>`. */
  trigger: (args: DisclosureRenderArgs) => ReactNode
  /** Content shown when open. */
  children: ReactNode
  defaultOpen?: boolean
  /** Controlled state; use with `onOpenChange`. */
  open?: boolean
  onOpenChange?: (open: boolean) => void
  /** Class for the content container. */
  contentClassName?: string
}

/**
 * One collapsible section with a trigger you render, for use inside lists and table rows.
 *
 *   <Disclosure trigger={({ open, triggerProps }) => (
 *     <button {...triggerProps} className="ui-disclosure-trigger">
 *       <DisclosureChevron open={open} /> Details
 *     </button>)}>
 *     …content…
 *   </Disclosure>
 */
export function Disclosure({
  trigger,
  children,
  defaultOpen = false,
  open,
  onOpenChange,
  className,
  contentClassName,
  ...rest
}: DisclosureProps) {
  const baseId = useId()
  const [inner, setInner] = useState(defaultOpen)
  const isOpen = open ?? inner
  const toggle = () => {
    if (open === undefined) setInner(!isOpen)
    onOpenChange?.(!isOpen)
  }
  const triggerId = `${baseId}-trigger`
  const contentId = `${baseId}-content`
  return (
    <div className={cx('ui-disclosure', isOpen && 'ui-disclosure--open', className)} {...rest}>
      {trigger({
        open: isOpen,
        toggle,
        triggerProps: { id: triggerId, type: 'button', 'aria-expanded': isOpen, 'aria-controls': contentId, onClick: toggle },
      })}
      <div id={contentId} className={cx('ui-disclosure__content', contentClassName)} hidden={!isOpen}>
        {children}
      </div>
    </div>
  )
}

/** 20px chevron that points down when closed and up when open. Decorative. */
export function DisclosureChevron({ open, className }: { open: boolean; className?: string }) {
  return (
    <span className={cx('ui-disclosure-chevron', open && 'ui-disclosure-chevron--open', className)} aria-hidden="true">
      <ChevronDownRegular fontSize={20} />
    </span>
  )
}
