import {
  createLightTheme,
  createDarkTheme,
  type BrandVariants,
  type Theme,
} from '@fluentui/react-components'
import type { RecordStatus } from './types/alm'

// A teal-through-cyan brand ramp. Routing is about flow, so the palette leans on the
// blue-green end rather than the default Power Platform indigo. Restrained: the brand
// shows up on primary actions and the source/target rule, nowhere else.
const brand: BrandVariants = {
  10: '#020404',
  20: '#0d1b1e',
  30: '#0f2d33',
  40: '#103b44',
  50: '#114a55',
  60: '#115967',
  70: '#0f6979',
  80: '#0b798c',
  90: '#0f889b',
  100: '#2f97a8',
  110: '#4aa6b5',
  120: '#65b5c2',
  130: '#80c4cf',
  140: '#9dd3dc',
  150: '#bbe1e8',
  160: '#daf0f4',
}

export const lightTheme: Theme = createLightTheme(brand)
export const darkTheme: Theme = createDarkTheme(brand)

// Diff status colors. Chosen for meaning, not decoration:
// missing needs adding, changed needs review, extra is left alone, equal is settled.
export const statusColor: Record<RecordStatus, { fg: string; bg: string; label: string }> = {
  MissingInTarget: { fg: '#0b5c2e', bg: '#e6f4ea', label: 'Missing in target' },
  Changed: { fg: '#8a5300', bg: '#fbf1e0', label: 'Changed' },
  ExtraInTarget: { fg: '#5b5b5b', bg: '#efefef', label: 'Extra in target' },
  Equal: { fg: '#2f7a4d', bg: 'transparent', label: 'Equal' },
}
