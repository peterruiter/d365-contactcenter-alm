import type { ImgHTMLAttributes } from 'react'
import logoBlue from '../assets/capgemini/capgemini-logo-blue.svg'
import logoWhite from '../assets/capgemini/capgemini-logo-white.svg'
import spadeBlue from '../assets/capgemini/capgemini-spade-blue.svg'
import spadeWhite from '../assets/capgemini/capgemini-spade-white.svg'
import { cx } from './utils'

export const CAPGEMINI_LOGOS = { logoBlue, logoWhite, spadeBlue, spadeWhite } as const

export interface CapgeminiLogoProps extends Omit<ImgHTMLAttributes<HTMLImageElement>, 'src'> {
  /** `lockup` (358x117) or `spade` (150x139). Default `lockup`. */
  mark?: 'lockup' | 'spade'
  /**
   * Pick by the ground: `blue` on page-background / surface-always-white, `white` on the heavy
   * blues. The ink is baked into the file; it is never recoloured. Default `blue`.
   */
  ink?: 'blue' | 'white'
}

/**
 * The 2025 Capgemini logo files. Minimum width 120px for the lockup, 32px for the spade; clear
 * space equal to the spade height on all sides is left to the container.
 */
export function CapgeminiLogo({ mark = 'lockup', ink = 'blue', alt = 'Capgemini', className, ...rest }: CapgeminiLogoProps) {
  const src = mark === 'spade' ? (ink === 'white' ? spadeWhite : spadeBlue) : ink === 'white' ? logoWhite : logoBlue
  return <img src={src} alt={alt} className={cx('ui-logo', `ui-logo--${mark}`, className)} {...rest} />
}
