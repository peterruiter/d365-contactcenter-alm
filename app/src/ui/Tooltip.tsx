import {
  cloneElement,
  isValidElement,
  useEffect,
  useId,
  useLayoutEffect,
  useRef,
  useState,
  type FocusEvent,
  type MouseEvent,
  type ReactElement,
  type ReactNode,
} from 'react'
import { cx } from './utils'

export interface TooltipProps {
  /** Short supplementary text. Never put essential information only in a tooltip. */
  content: ReactNode
  /** One focusable element (a button, link or input). It gets aria-describedby. */
  children: ReactElement
  /** Default `top`; flips to fit is not attempted, but it shifts to stay inside the viewport. */
  placement?: 'top' | 'bottom'
  /** Hover delay in ms. Default 300. Focus shows it immediately. */
  delay?: number
  className?: string
}

type TriggerProps = {
  'aria-describedby'?: string
  onMouseEnter?: (e: MouseEvent) => void
  onFocus?: (e: FocusEvent) => void
  onBlur?: (e: FocusEvent) => void
}

/**
 * Tooltip on hover and focus. role="tooltip" linked by aria-describedby; Escape hides it; the
 * bubble is hoverable (it sits inside the wrapper), per WCAG 1.4.13. surface-ink-heavy with
 * text-always-white.
 */
export function Tooltip({ content, children, placement = 'top', delay = 300, className }: TooltipProps) {
  const id = useId()
  const [open, setOpen] = useState(false)
  const [shift, setShift] = useState(0)
  const timer = useRef<number>()
  const bubble = useRef<HTMLSpanElement>(null)

  const show = (now: boolean) => {
    window.clearTimeout(timer.current)
    if (now) setOpen(true)
    else timer.current = window.setTimeout(() => setOpen(true), delay)
  }
  const hide = () => {
    window.clearTimeout(timer.current)
    setOpen(false)
  }

  useEffect(() => () => window.clearTimeout(timer.current), [])

  useEffect(() => {
    if (!open) return
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') hide()
    }
    document.addEventListener('keydown', onKey)
    return () => document.removeEventListener('keydown', onKey)
  }, [open])

  // Keep the bubble inside the viewport horizontally (16px gutter).
  useLayoutEffect(() => {
    if (!open || !bubble.current) {
      setShift(0)
      return
    }
    const r = bubble.current.getBoundingClientRect()
    const gutter = 16
    const left = r.left - shift
    const right = r.right - shift
    if (left < gutter) setShift(gutter - left)
    else if (right > window.innerWidth - gutter) setShift(window.innerWidth - gutter - right)
    else setShift(0)
  }, [open, content])

  if (!isValidElement(children)) return children
  const child = children as ReactElement<TriggerProps>
  const describedBy = [child.props['aria-describedby'], id].filter(Boolean).join(' ')

  const trigger = cloneElement(child, {
    'aria-describedby': describedBy,
    onFocus: (e: FocusEvent) => {
      child.props.onFocus?.(e)
      show(true)
    },
    onBlur: (e: FocusEvent) => {
      child.props.onBlur?.(e)
      hide()
    },
  })

  return (
    <span className={cx('ui-tooltip', className)} onMouseEnter={() => show(false)} onMouseLeave={hide}>
      {trigger}
      <span
        ref={bubble}
        id={id}
        role="tooltip"
        className={cx('ui-tooltip__bubble', `ui-tooltip__bubble--${placement}`, open && 'ui-tooltip__bubble--open')}
        style={{ ['--ui-tooltip-shift' as string]: `${shift}px` }}
      >
        {content}
      </span>
    </span>
  )
}
