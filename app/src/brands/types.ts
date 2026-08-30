import type { BrandVariants } from '@fluentui/react-components'

// One brand = one visual identity for the app shell: logo, colors, page chrome.
// Mirrors the brands/<id>.json pattern from the sibling d365-contactcenter-estimator
// project, adapted to a React/Vite app instead of a static-HTML build step - the brand
// is picked once at build/runtime via VITE_BRAND instead of producing one file per brand.
export interface Brand {
  id: string
  name: string
  /** Browser tab title. */
  productTitle: string
  /** Header subtitle, next to the product name. */
  headerSubtitle: string
  /** Logo shown in the header. Always rendered on the colored header background, so this must be a light/white variant. */
  logoLight: string
  /** Alt text for the header logo. */
  logoAlt: string
  /** Favicon href (an imported asset URL). */
  favicon: string
  colors: {
    /** Header gradient end, links, brand primary. Fluent ramp stop 80. */
    primary: string
    /** Header gradient start, darker end of the brand. */
    primaryDark: string
    /** Header bottom border and small accent uses. */
    accent: string
  }
  /** Full 16-stop Fluent brand ramp (10 darkest -> 160 white), stop 80 = colors.primary. */
  ramp: BrandVariants
  footer: BrandFooter
}

// Mirrors the footer in the sibling d365-contactcenter-estimator project: a brand line (icon +
// name + link), a one-line disclaimer, then a muted "creator" line with contact links. There the
// whole thing is one HTML string per brand; here it is structured so the footer component can
// render it as real JSX instead of dangerouslySetInnerHTML.
export interface BrandFooter {
  /** Small icon shown before the brand name (an imported asset URL). */
  icon: string
  /** e.g. "Capgemini · Make it real." or "Power Pete". */
  tagline: string
  /** Where the tagline links to. */
  taglineHref: string
  /** One line, tool-specific caveat. */
  disclaimer: string
  creator: {
    /** Text before the (bolded) name, e.g. "Created by" or "Want a hand running this for real?". */
    before: string
    /** The name itself, rendered bold - e.g. "Peter Ruiter". */
    name: string
    /** Text after the name, e.g. ", Global Microsoft Dynamics 365 Contact Center lead, Capgemini". */
    after: string
    mailHref: string
    teamsHref: string
    /** Label for the third link, e.g. "powerpete.com" or "LinkedIn". */
    extraLabel: string
    extraHref: string
  }
}
