import { createLightTheme, createDarkTheme, type Theme } from '@fluentui/react-components'
import type { RecordStatus } from './types/alm'
import { brand } from './brands'

export const lightTheme: Theme = createLightTheme(brand.ramp)
export const darkTheme: Theme = createDarkTheme(brand.ramp)

// Diff status colors, grounded in the Zodiak design system's Green (positive), Orange
// (attention), and Neutral primitive families - kept stable across brands since these are
// diff-status semantics, not brand chrome. Meaning over decoration: missing needs adding,
// changed needs review, extra is left alone, equal is settled. Each carries fg/bg/dot plus a label.
export interface StatusStyle {
  fg: string
  bg: string
  dot: string
  label: string
}

export const statusColor: Record<RecordStatus, StatusStyle> = {
  MissingInTarget: { fg: '#1e5631', bg: '#eff7f5', dot: '#4eb972', label: 'Missing in target' }, // Green-800 / surface-positive / Green-600
  Changed: { fg: '#cc640f', bg: '#ffe5d3', dot: '#f68f40', label: 'Changed' }, // Orange-700 / Orange-100 / Orange-500
  ExtraInTarget: { fg: '#6e7480', bg: '#e9edf3', dot: '#a6acb5', label: 'Extra in target' }, // Neutral-500 / Neutral-200 / Neutral-400
  Equal: { fg: '#43a063', bg: 'transparent', dot: '#57cf80', label: 'Equal' }, // Green-700 / Green-500
}
