import { useEffect, useId, useRef, type ReactNode } from 'react'
import { DismissRegular } from '@fluentui/react-icons'
import { IconButton } from './IconButton'
import { cx } from './utils'

export interface DialogProps {
  open: boolean
  /** Called on Escape, the close button, a backdrop click (if enabled) or `dialog.close()`. */
  onClose: () => void
  /** Heading; labels the dialog. */
  title: ReactNode
  /** Optional lead text under the title; describes the dialog. */
  description?: ReactNode
  children?: ReactNode
  /** Buttons, right-aligned. Put the primary action last. */
  actions?: ReactNode
  /** Hide the top-right close button (Escape still closes). */
  hideClose?: boolean
  /** Default "Close". */
  closeLabel?: string
  /** Close when the backdrop is clicked. Default false. */
  closeOnBackdrop?: boolean
  className?: string
}

/**
 * Modal on the native <dialog> with showModal(): the browser traps focus, makes the rest inert and
 * closes on Escape. Focus returns to the opener when it closes.
 */
export function Dialog({
  open,
  onClose,
  title,
  description,
  children,
  actions,
  hideClose,
  closeLabel = 'Close',
  closeOnBackdrop,
  className,
}: DialogProps) {
  const ref = useRef<HTMLDialogElement>(null)
  const titleId = useId()
  const descId = useId()
  const openRef = useRef(open)
  openRef.current = open
  const onCloseRef = useRef(onClose)
  onCloseRef.current = onClose

  // Counts close() calls made here, so their (async) close events are not reported as user closes.
  const ownCloses = useRef(0)

  useEffect(() => {
    const el = ref.current
    if (!el) return
    if (open && !el.open) {
      const opener = document.activeElement as HTMLElement | null
      el.showModal()
      return () => {
        if (el.open) {
          ownCloses.current++
          el.close()
        }
        opener?.focus?.()
      }
    }
  }, [open])

  useEffect(() => {
    const el = ref.current
    if (!el) return
    // Escape: let the parent decide by calling onClose; the open prop drives the element.
    const onCancel = (e: Event) => {
      e.preventDefault()
      onCloseRef.current()
    }
    // A native close we did not ask for (e.g. the browser ignoring preventDefault on repeat Escape).
    const onNativeClose = () => {
      if (ownCloses.current > 0) {
        ownCloses.current--
        return
      }
      if (openRef.current) onCloseRef.current()
    }
    el.addEventListener('cancel', onCancel)
    el.addEventListener('close', onNativeClose)
    return () => {
      el.removeEventListener('cancel', onCancel)
      el.removeEventListener('close', onNativeClose)
    }
  }, [])

  return (
    <dialog
      ref={ref}
      className={cx('ui-dialog', className)}
      aria-labelledby={titleId}
      aria-describedby={description ? descId : undefined}
      onClick={(e) => {
        if (closeOnBackdrop && e.target === e.currentTarget) onClose()
      }}
    >
      {open && (
        <div className="ui-dialog__surface">
          <div className="ui-dialog__header">
            <h2 id={titleId} className="ui-dialog__title t-h4">
              {title}
            </h2>
            {!hideClose && (
              <IconButton quiet size="sm" label={closeLabel} icon={<DismissRegular fontSize={20} />} onClick={onClose} />
            )}
          </div>
          {description && (
            <p id={descId} className="ui-dialog__description">
              {description}
            </p>
          )}
          {children !== undefined && children !== null && <div className="ui-dialog__body">{children}</div>}
          {actions && <div className="ui-dialog__actions">{actions}</div>}
        </div>
      )}
    </dialog>
  )
}
