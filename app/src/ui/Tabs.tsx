import { useId, useRef, type HTMLAttributes, type KeyboardEvent, type ReactNode } from 'react'
import { Badge } from './Badge'
import { cx, type Tone } from './utils'

export interface TabItem {
  id: string
  label: string
  /** Count shown after the label (rendered as a Badge). */
  badge?: ReactNode
  disabled?: boolean
}

export interface TabsProps {
  items: TabItem[]
  selected: string
  onSelect: (id: string) => void
  /** Accessible name for the tablist. */
  'aria-label'?: string
  'aria-labelledby'?: string
  /** `heavy` on surface-ink-heavy (e.g. in AppHeader): white labels, turquoise indicator. Default `lite`. */
  tone?: Tone
  /** `auto` selects on arrow-key focus; `manual` waits for Enter/Space. Default `auto`. */
  activation?: 'auto' | 'manual'
  /** Shared id base. When set, tabs get aria-controls pointing at `<TabPanel idBase=…>`. */
  idBase?: string
  className?: string
}

const tabId = (base: string, id: string) => `${base}-tab-${id}`
const panelId = (base: string, id: string) => `${base}-panel-${id}`

/** Tablist with roving tabindex, arrow/Home/End keys and a 3px active underline. */
export function Tabs({
  items,
  selected,
  onSelect,
  tone = 'lite',
  activation = 'auto',
  idBase,
  className,
  'aria-label': ariaLabel,
  'aria-labelledby': ariaLabelledBy,
}: TabsProps) {
  const autoBase = useId()
  const base = idBase ?? autoBase
  const refs = useRef<Array<HTMLButtonElement | null>>([])
  const enabled = items.map((it, i) => (it.disabled ? -1 : i)).filter((i) => i >= 0)
  const selectedIndex = items.findIndex((it) => it.id === selected)
  const tabStop = selectedIndex >= 0 && !items[selectedIndex].disabled ? selectedIndex : enabled[0]

  const onKeyDown = (e: KeyboardEvent<HTMLButtonElement>, index: number) => {
    const pos = enabled.indexOf(index)
    let next: number | undefined
    if (e.key === 'ArrowRight') next = enabled[(pos + 1) % enabled.length]
    else if (e.key === 'ArrowLeft') next = enabled[(pos - 1 + enabled.length) % enabled.length]
    else if (e.key === 'Home') next = enabled[0]
    else if (e.key === 'End') next = enabled[enabled.length - 1]
    if (next === undefined) return
    e.preventDefault()
    refs.current[next]?.focus()
    if (activation === 'auto') onSelect(items[next].id)
  }

  return (
    <div
      role="tablist"
      aria-label={ariaLabel}
      aria-labelledby={ariaLabelledBy}
      aria-orientation="horizontal"
      className={cx('ui-tabs', `ui-tabs--${tone}`, tone === 'heavy' && 'ui-on-heavy', className)}
    >
      {items.map((item, i) => {
        const isSelected = item.id === selected
        return (
          <button
            key={item.id}
            ref={(el) => (refs.current[i] = el)}
            type="button"
            role="tab"
            id={tabId(base, item.id)}
            aria-selected={isSelected}
            aria-controls={idBase ? panelId(base, item.id) : undefined}
            tabIndex={i === tabStop ? 0 : -1}
            disabled={item.disabled}
            className={cx('ui-tab', isSelected && 'ui-tab--selected')}
            onClick={() => onSelect(item.id)}
            onKeyDown={(e) => onKeyDown(e, i)}
          >
            <span className="ui-tab__label" data-label={item.label}>
              {item.label}
            </span>
            {item.badge !== undefined && item.badge !== null && (
              <Badge tone={tone === 'heavy' ? 'strong' : 'default'} className="ui-tab__badge">
                {item.badge}
              </Badge>
            )}
          </button>
        )
      })}
    </div>
  )
}

export interface TabPanelProps extends HTMLAttributes<HTMLDivElement> {
  /** Same `idBase` given to Tabs. */
  idBase: string
  /** The tab id this panel belongs to. */
  tabId: string
  /** Whether this panel's tab is selected; unselected panels are hidden. */
  selected: boolean
}

/** Panel paired with a Tabs item through `idBase`. */
export function TabPanel({ idBase, tabId: forTab, selected, className, ...rest }: TabPanelProps) {
  return (
    <div
      role="tabpanel"
      id={panelId(idBase, forTab)}
      aria-labelledby={tabId(idBase, forTab)}
      hidden={!selected}
      tabIndex={0}
      className={cx('ui-tabpanel', className)}
      {...rest}
    />
  )
}
