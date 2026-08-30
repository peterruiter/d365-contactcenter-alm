import type { BrandVariants } from '@fluentui/react-components'
import type { Brand } from './types'
import logo from '../assets/powerpete-logo-white.svg'
import favicon from '../assets/powerpete-icon.png'

// Power Pete palette (powerpete.com), same ramp shape as the Capgemini one in ./capgemini.ts -
// stops 10-70 darken toward the deep purple anchor, stop 80 is the brand primary, 90-160
// lighten toward white.
const ramp: BrandVariants = {
  10: '#030106',
  20: '#0a0616',
  30: '#150e2e',
  40: '#1e1440',
  50: '#251a6e', // pp-purple-deep
  60: '#2e2186',
  70: '#33269c',
  80: '#3b2a9e', // pp-purple, brand primary
  90: '#5847b5',
  100: '#7566c4',
  110: '#9686d3',
  120: '#b8ade0',
  130: '#d4cceb',
  140: '#e9e4f5',
  150: '#f6f3fb',
  160: '#ffffff',
}

export const powerpete: Brand = {
  id: 'powerpete',
  name: 'Power Pete',
  productTitle: 'Contact Center ALM Accelerator',
  headerSubtitle: 'No CMT, no manual GUID edits - just compare, move, and roll back.',
  logoLight: logo,
  logoAlt: 'Power Pete',
  favicon,
  colors: {
    primary: '#3b2a9e', // pp-purple
    primaryDark: '#251a6e', // pp-purple-deep
    accent: '#2ed3b7', // pp-mint
  },
  ramp,
  footer: {
    icon: favicon,
    tagline: 'Power Pete',
    taglineHref: 'https://powerpete.com',
    disclaimer:
      "Writes Contact Center config straight through the Dataverse Web API, because CMT can't reach half of this. Dry-run first, test on Dev/Test before Prod.",
    creator: {
      before: 'Want a hand running this for real?',
      name: 'Peter Ruiter',
      after: ' is the Global Microsoft Dynamics 365 Contact Center lead at Capgemini',
      mailHref: 'mailto:peter.ruiter@capgemini.com?subject=Contact%20Center%20ALM',
      teamsHref: 'https://teams.microsoft.com/l/chat/0/0?users=peter.ruiter@capgemini.com',
      extraLabel: 'LinkedIn',
      extraHref: 'https://www.linkedin.com/in/peterruiter/',
    },
  },
}
