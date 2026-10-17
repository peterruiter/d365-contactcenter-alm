import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react'
import { Notice, type NoticeTone } from './Notice'

export interface ToastOptions {
  tone?: NoticeTone
  title?: ReactNode
  message?: ReactNode
  /** One small action (Button size="sm" or Link). */
  action?: ReactNode
  /** Milliseconds before auto-dismiss. Default 6000; 0 keeps it until dismissed. */
  duration?: number
}

interface ToastEntry extends ToastOptions {
  id: number
}

export interface ToastApi {
  /** Shows a toast and returns its id. */
  toast: (options: ToastOptions) => number
  dismiss: (id: number) => void
}

const ToastContext = createContext<ToastApi | null>(null)

/** Access the nearest Toaster. */
export function useToast(): ToastApi {
  const ctx = useContext(ToastContext)
  if (!ctx) throw new Error('useToast must be used inside <Toaster>')
  return ctx
}

export interface ToasterProps {
  children?: ReactNode
  /** Accessible name of the notification region. Default "Notifications". */
  label?: string
}

/**
 * Provider plus the polite live region, fixed bottom-right. Wrap the app once. Timers pause while
 * the pointer or focus is inside the region, so nobody loses a toast mid-read.
 */
export function Toaster({ children, label = 'Notifications' }: ToasterProps) {
  const [toasts, setToasts] = useState<ToastEntry[]>([])
  const nextId = useRef(1)
  const [paused, setPaused] = useState(false)

  const dismiss = useCallback((id: number) => setToasts((list) => list.filter((t) => t.id !== id)), [])
  const toast = useCallback((options: ToastOptions) => {
    const id = nextId.current++
    setToasts((list) => [...list, { duration: 6000, tone: 'info', ...options, id }])
    return id
  }, [])
  const api = useMemo(() => ({ toast, dismiss }), [toast, dismiss])

  return (
    <ToastContext.Provider value={api}>
      {children}
      <section
        className="ui-toaster"
        aria-label={label}
        onMouseEnter={() => setPaused(true)}
        onMouseLeave={() => setPaused(false)}
        onFocus={() => setPaused(true)}
        onBlur={(e) => {
          if (!e.currentTarget.contains(e.relatedTarget as Node | null)) setPaused(false)
        }}
      >
        <div className="ui-toaster__list" aria-live="polite" aria-relevant="additions text">
          {toasts.map((t) => (
            <ToastItem key={t.id} entry={t} paused={paused} onDismiss={dismiss} />
          ))}
        </div>
      </section>
    </ToastContext.Provider>
  )
}

function ToastItem({ entry, paused, onDismiss }: { entry: ToastEntry; paused: boolean; onDismiss: (id: number) => void }) {
  const remaining = useRef(entry.duration ?? 6000)
  useEffect(() => {
    if (!entry.duration || paused) return
    const started = Date.now()
    const timer = window.setTimeout(() => onDismiss(entry.id), remaining.current)
    return () => {
      window.clearTimeout(timer)
      remaining.current = Math.max(1000, remaining.current - (Date.now() - started))
    }
  }, [paused, entry.duration, entry.id, onDismiss])

  return (
    <Notice
      className="ui-toast"
      tone={entry.tone}
      title={entry.title}
      live="none"
      actions={entry.action}
      onDismiss={() => onDismiss(entry.id)}
    >
      {entry.message}
    </Notice>
  )
}
