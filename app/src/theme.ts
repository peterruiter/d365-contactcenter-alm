import {
  createLightTheme,
  createDarkTheme,
  type BrandVariants,
  type Theme,
} from '@fluentui/react-components'
import type { RecordStatus } from './types/alm'

// Capgemini brand ramp. Anchored on Capgemini Blue #0070AD (primary, ~stop 80) and rising
// through Vibrant Blue #17ABDA (accent, ~stop 100) into pale tints. Deep navy at the low end.
const brand: BrandVariants = {
  10: '#001523',
  20: '#00263f',
  30: '#00375b',
  40: '#004977',
  50: '#005a93',
  60: '#0064a3',
  70: '#006aa8',
  80: '#0070ad', // Capgemini Blue
  90: '#1088c1',
  100: '#17abda', // Vibrant Blue
  110: '#40b9e0',
  120: '#64c6e7',
  130: '#88d3ee',
  140: '#abe0f4',
  150: '#cdeef9',
  160: '#e8f7fc',
}

export const lightTheme: Theme = createLightTheme(brand)
export const darkTheme: Theme = createDarkTheme(brand)

// Fixed brand values used in the header and accents, independent of light/dark tokens.
export const capgemini = {
  blue: '#0070ad',
  blueDark: '#005b8f',
  vibrant: '#17abda',
}

// Diff status colors. Meaning over decoration: missing needs adding, changed needs review,
// extra is left alone, equal is settled. Each carries a light and dark variant.
export interface StatusStyle {
  fg: string
  bg: string
  dot: string
  label: string
}

export const statusColor: Record<RecordStatus, StatusStyle> = {
  MissingInTarget: { fg: '#0e6b2e', bg: '#e4f6ea', dot: '#1a9e4b', label: 'Missing in target' },
  Changed: { fg: '#8a5a00', bg: '#fdf3e2', dot: '#e08600', label: 'Changed' },
  ExtraInTarget: { fg: '#5b6675', bg: '#eef1f5', dot: '#8a97a8', label: 'Extra in target' },
  Equal: { fg: '#2f7a4d', bg: 'transparent', dot: '#57b98a', label: 'Equal' },
}
