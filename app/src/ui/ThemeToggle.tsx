import { useCallback, useEffect, useSyncExternalStore } from 'react'
import { Switch } from './Switch'
import type { Tone } from './utils'

export type Theme = 'light' | 'dark'

const STORAGE_KEY = 'cgz-theme'
const listeners = new Set<() => void>()
let current: Theme | null = null

function readStored(): Theme | null {
  try {
    const v = window.localStorage.getItem(STORAGE_KEY)
    return v === 'light' || v === 'dark' ? v : null
  } catch {
    return null
  }
}

function systemTheme(): Theme {
  try {
    return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'
  } catch {
    return 'light'
  }
}

function apply(theme: Theme) {
  current = theme
  if (typeof document !== 'undefined') document.documentElement.setAttribute('data-theme', theme)
  listeners.forEach((l) => l())
}

/**
 * Sets data-theme on <html> from the stored choice, else prefers-color-scheme. Safe to call more
 * than once. Call it before the first render to avoid a light flash; useTheme() also calls it.
 */
export function initTheme(): Theme {
  if (current) return current
  if (typeof window === 'undefined') return 'light'
  // No listener notification here: this also runs as the store snapshot during render.
  current = readStored() ?? systemTheme()
  document.documentElement.setAttribute('data-theme', current)
  return current
}

/** Sets and persists the theme. */
export function setTheme(theme: Theme) {
  try {
    window.localStorage.setItem(STORAGE_KEY, theme)
  } catch {
    /* storage blocked: the choice lasts for this page only */
  }
  apply(theme)
}

function subscribe(listener: () => void) {
  listeners.add(listener)
  return () => {
    listeners.delete(listener)
  }
}

/** Current theme plus setters. Follows the OS setting until the user picks one. */
export function useTheme(): { theme: Theme; setTheme: (t: Theme) => void; toggle: () => void } {
  const theme = useSyncExternalStore(subscribe, initTheme, () => 'light' as Theme)

  useEffect(() => {
    let mq: MediaQueryList
    try {
      mq = window.matchMedia('(prefers-color-scheme: dark)')
    } catch {
      return
    }
    const onChange = () => {
      if (!readStored()) apply(mq.matches ? 'dark' : 'light')
    }
    mq.addEventListener('change', onChange)
    return () => mq.removeEventListener('change', onChange)
  }, [])

  const toggle = useCallback(() => setTheme((current ?? 'light') === 'dark' ? 'light' : 'dark'), [])
  return { theme, setTheme, toggle }
}

export interface ThemeToggleProps {
  /** Default "Dark theme". */
  label?: string
  hideLabel?: boolean
  /** `heavy` when placed in AppHeader. Default `lite`. */
  tone?: Tone
  className?: string
}

/** Switch that flips data-theme between light and dark and remembers the choice. */
export function ThemeToggle({ label = 'Dark theme', hideLabel, tone = 'lite', className }: ThemeToggleProps) {
  const { theme, setTheme: set } = useTheme()
  return (
    <Switch
      checked={theme === 'dark'}
      onChange={(on) => set(on ? 'dark' : 'light')}
      label={label}
      hideLabel={hideLabel}
      tone={tone}
      className={className}
    />
  )
}
