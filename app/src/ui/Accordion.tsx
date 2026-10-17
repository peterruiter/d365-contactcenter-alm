import { useId, useState, type ReactNode } from 'react'
import { ChevronDownRegular } from '@fluentui/react-icons'
import { cx } from './utils'

export interface AccordionItem {
  /** Stable key; defaults to the index. */
  id?: string
  title: ReactNode
  content: ReactNode
}

export interface AccordionProps {
  items: AccordionItem[]
  /** Index open on first render. Omit to start closed. */
  defaultOpen?: number
  /** Controlled open index (`null` = all closed). Use with `onOpenChange`. */
  open?: number | null
  onOpenChange?: (index: number | null) => void
  /** Heading level that wraps each title button. Default 3. */
  headingLevel?: 2 | 3 | 4 | 5
  className?: string
}

/** One panel open at a time. Titles are buttons with aria-expanded/aria-controls inside headings. */
export function Accordion({ items, defaultOpen, open, onOpenChange, headingLevel = 3, className }: AccordionProps) {
  const baseId = useId()
  const [inner, setInner] = useState<number | null>(defaultOpen ?? null)
  const current = open !== undefined ? open : inner
  const Heading = `h${headingLevel}` as 'h3'

  const toggle = (i: number) => {
    const next = current === i ? null : i
    if (open === undefined) setInner(next)
    onOpenChange?.(next)
  }

  return (
    <div className={cx('cgz-accordion', className)}>
      {items.map((item, i) => {
        const isOpen = current === i
        const triggerId = `${baseId}-t${i}`
        const panelId = `${baseId}-p${i}`
        return (
          <div key={item.id ?? i} className={cx('cgz-accordion__item', isOpen && 'cgz-accordion__item--open')}>
            <Heading className="cgz-accordion__heading">
              <button
                type="button"
                id={triggerId}
                className="cgz-accordion__title"
                aria-expanded={isOpen}
                aria-controls={panelId}
                onClick={() => toggle(i)}
              >
                <span className="cgz-accordion__chevron" aria-hidden="true">
                  <ChevronDownRegular fontSize={24} />
                </span>
                <span className="cgz-accordion__label">{item.title}</span>
              </button>
            </Heading>
            <div id={panelId} role="region" aria-labelledby={triggerId} className="cgz-accordion__content" hidden={!isOpen}>
              {item.content}
            </div>
          </div>
        )
      })}
    </div>
  )
}
