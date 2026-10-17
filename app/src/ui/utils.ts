import type { MutableRefObject, Ref } from 'react'

/** Joins class names, skipping falsy values. */
export function cx(...parts: Array<string | false | null | undefined>): string {
  return parts.filter(Boolean).join(' ')
}

/** Assigns one node to several refs (callback or object). */
export function setRefs<T>(node: T | null, ...refs: Array<Ref<T> | undefined>): void {
  for (const ref of refs) {
    if (!ref) continue
    if (typeof ref === 'function') ref(node)
    else (ref as MutableRefObject<T | null>).current = node
  }
}

/** The ground a control sits on: lite surfaces or the heavy blues. Pick by the ground, not the theme. */
export type Tone = 'lite' | 'heavy'
