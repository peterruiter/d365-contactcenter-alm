// Which build this is (stamped by vite.config.ts), and the latest local runner release on GitHub.

export interface BuildInfo {
  version: string
  /** Commit count on the branch at build time: a newer build has a higher number. */
  build: number
  commit: string
  builtAt: string
}

export const BUILD: BuildInfo = __CCALM_BUILD__

export function buildLabel(b: BuildInfo = BUILD) {
  return `Version ${b.version} · build ${b.build} (${b.commit})`
}

/** What the local runner found on GitHub (GET /api/update). */
export interface UpdateInfo {
  latest: BuildInfo | null
  releaseUrl: string
  checkedAt: string | null
  error?: string | null
}

export function isNewer(latest: BuildInfo | null | undefined, current: BuildInfo = BUILD) {
  return !!latest && Number(latest.build) > Number(current.build)
}

const DISMISSED = 'ccalm.updateDismissed'

export function isDismissed(build: number) {
  try {
    return localStorage.getItem(DISMISSED) === String(build)
  } catch {
    return false
  }
}

export function dismiss(build: number) {
  try {
    localStorage.setItem(DISMISSED, String(build))
  } catch {
    // Private window or blocked storage: the banner simply comes back next time.
  }
}
