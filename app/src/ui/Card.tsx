import type { HTMLAttributes, ReactNode } from 'react'
import { cx } from './utils'

export interface CardProps extends Omit<HTMLAttributes<HTMLElement>, 'title'> {
  /** Image URL; scales 1.1x on card hover. */
  image?: string
  /** Alt text. Pass "" when the image is decorative. */
  imageAlt?: string
  /** Category label above the title, with the turquoise sweep. */
  eyebrow?: ReactNode
  eyebrowHref?: string
  title?: ReactNode
  /** Links the title; card hover sweeps it. Do not make the whole card a link. */
  href?: string
  /** Heading element for the title. Default `h3`. */
  titleAs?: 'h2' | 'h3' | 'h4' | 'h5'
  /** One value, or several joined by the 4px dot separator. */
  meta?: ReactNode | ReactNode[]
  /** One action, usually a small Button or a Link. */
  footer?: ReactNode
  /** Adds the border-primary outline and the space-6 inset (space-5 below 768px). No shadow. */
  bordered?: boolean
}

/** The Capgemini content card. No width and (unless `bordered`) no inset of its own; no shadow. */
export function Card({
  image,
  imageAlt = '',
  eyebrow,
  eyebrowHref,
  title,
  href,
  titleAs: TitleTag = 'h3',
  meta,
  footer,
  bordered,
  className,
  children,
  ...rest
}: CardProps) {
  const metaItems = meta === undefined || meta === null ? [] : Array.isArray(meta) ? meta : [meta]
  return (
    <article className={cx('cgz-card', bordered && 'cgz-card--bordered', className)} {...rest}>
      {image && (
        <div className="cgz-card__media">
          <img src={image} alt={imageAlt} />
        </div>
      )}
      {eyebrow &&
        (eyebrowHref ? (
          <a className="cgz-card__eyebrow" href={eyebrowHref}>
            {eyebrow}
          </a>
        ) : (
          <span className="cgz-card__eyebrow">{eyebrow}</span>
        ))}
      {title && <TitleTag className="cgz-card__title">{href ? <a href={href}>{title}</a> : title}</TitleTag>}
      {metaItems.length > 0 && (
        <span className="cgz-card__meta">
          {metaItems.map((m, i) => (
            <span key={i}>{m}</span>
          ))}
        </span>
      )}
      {children !== undefined && children !== null && <div className="cgz-card__body">{children}</div>}
      {footer && <div className="cgz-card__footer">{footer}</div>}
    </article>
  )
}
