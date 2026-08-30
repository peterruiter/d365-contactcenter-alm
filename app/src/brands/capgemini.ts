import type { BrandVariants } from '@fluentui/react-components'
import type { Brand } from './types'
import logo from '../assets/capgemini-logo-white.svg'
import favicon from '../assets/capgemini-spade-blue.svg'

// Built from the real Zodiak design system primitive scale
// (doc-zodiak.capgemini.com > Foundations > Color > Primitive colors, "CapgeminiBlue" family).
// Stop 80 carries the exact brand primary CapgeminiBlue-500 (#0058ab), matching Fluent's
// convention of using stop 80 as the interactive/primary color.
const ramp: BrandVariants = {
  10: '#010204', // CapgeminiBlue-1000
  20: '#070a16', // CapgeminiBlue-950
  30: '#121a38', // CapgeminiBlue-900
  40: '#1d365a', // CapgeminiBlue-800
  50: '#1c4076', // CapgeminiBlue-700
  60: '#264f96', // CapgeminiBlue-600
  70: '#1353a0', // blended 600 -> 500
  80: '#0058ab', // CapgeminiBlue-500 (Capgemini Blue, brand primary)
  90: '#3573c0', // CapgeminiBlue-400
  100: '#5685c6', // CapgeminiBlue-300
  110: '#8ea6d5', // CapgeminiBlue-200
  120: '#c0cce4', // blended 200 -> 100
  130: '#dfe1eb', // CapgeminiBlue-100
  140: '#eff0f4', // CapgeminiBlue-50
  150: '#fcfcfc', // CapgeminiBlue-25
  160: '#ffffff',
}

export const capgemini: Brand = {
  id: 'capgemini',
  name: 'Capgemini',
  productTitle: 'Contact Center ALM Accelerator',
  headerSubtitle: 'No CMT, no manual GUID edits - just compare, move, and roll back.',
  logoLight: logo,
  logoAlt: 'Capgemini',
  favicon,
  colors: {
    primary: '#0058ab', // surface-azur-heavy
    primaryDark: '#1c4076', // surface-marine-heavy
    accent: '#00d5d0', // Teal-600, Zodiak accent color
  },
  ramp,
  footer: {
    icon: favicon,
    tagline: 'Capgemini · Make it real.',
    taglineHref: 'https://www.capgemini.com',
    disclaimer:
      "Writes Contact Center config straight through the Dataverse Web API, because CMT can't reach half of this. Dry-run first, test on Dev/Test before Prod.",
    creator: {
      before: 'Built by',
      name: 'Peter Ruiter',
      after: ', Global Microsoft Dynamics 365 Contact Center lead & CTO Dynamics 365 CX, Capgemini',
      mailHref: 'mailto:peter.ruiter@capgemini.com?subject=Contact%20Center%20ALM',
      teamsHref: 'https://teams.microsoft.com/l/chat/0/0?users=peter.ruiter@capgemini.com',
      extraLabel: 'powerpete.com',
      extraHref: 'https://powerpete.com',
    },
  },
}
