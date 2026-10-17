import {
  forwardRef,
  type CSSProperties,
  type HTMLAttributes,
  type ReactNode,
  type TableHTMLAttributes,
  type TdHTMLAttributes,
  type ThHTMLAttributes,
} from 'react'
import { cx } from './utils'

export interface TableProps extends TableHTMLAttributes<HTMLTableElement> {
  /** Accessible name. Always set it. */
  caption?: ReactNode
  /** Show the caption visibly above the table (t-body-small, text-secondary). Default hidden. */
  showCaption?: boolean
  /** Sticky header. Sticks to the page, or to the wrapper when `maxHeight` is set. */
  sticky?: boolean
  /** Makes the wrapper scroll vertically (e.g. "60vh"); the sticky header then sticks inside it. */
  maxHeight?: CSSProperties['maxHeight']
  /** Class for the scroll wrapper. */
  wrapperClassName?: string
}

/**
 * Real `<table>` with the Zodiak DataTable look. Wrapped in a horizontally scrolling container
 * so wide tables never push the page past 360px. (A page-sticky header needs that wrapper not to
 * scroll, so `sticky` without `maxHeight` lets wide tables overflow their wrapper instead.)
 */
export const Table = forwardRef<HTMLTableElement, TableProps>(function Table(
  { caption, showCaption, sticky, maxHeight, wrapperClassName, className, children, ...rest },
  ref,
) {
  const scroll = !sticky || maxHeight !== undefined
  return (
    <div
      className={cx('cgz-table-wrap', scroll && 'cgz-table-wrap--scroll', wrapperClassName)}
      style={maxHeight !== undefined ? { maxHeight } : undefined}
    >
      <table ref={ref} className={cx('cgz-table', sticky && 'cgz-table--sticky', className)} {...rest}>
        {caption !== undefined && caption !== null && (
          <caption className={showCaption ? 'cgz-table__caption' : 'ui-visually-hidden'}>{caption}</caption>
        )}
        {children}
      </table>
    </div>
  )
})

export function THead({ className, ...rest }: HTMLAttributes<HTMLTableSectionElement>) {
  return <thead className={cx('cgz-table__head', className)} {...rest} />
}

export function TBody({ className, ...rest }: HTMLAttributes<HTMLTableSectionElement>) {
  return <tbody className={cx('cgz-table__body', className)} {...rest} />
}

export interface TrProps extends HTMLAttributes<HTMLTableRowElement> {
  /** Selected row: surface-cloud-lite fill. Pair it with a checked checkbox; the fill is not enough on its own. */
  selected?: boolean
  /** Turn off the hover fill (e.g. header rows, detail rows). */
  noHover?: boolean
}

export const Tr = forwardRef<HTMLTableRowElement, TrProps>(function Tr({ selected, noHover, className, ...rest }, ref) {
  return (
    <tr
      ref={ref}
      data-selected={selected || undefined}
      className={cx('cgz-table__row', selected && 'cgz-table__row--selected', noHover && 'cgz-table__row--static', className)}
      {...rest}
    />
  )
})

export interface ThProps extends ThHTMLAttributes<HTMLTableCellElement> {
  /** Right-align (numbers). */
  numeric?: boolean
}

export function Th({ numeric, scope = 'col', className, ...rest }: ThProps) {
  return <th scope={scope} className={cx('cgz-table__th', numeric && 'cgz-table__cell--numeric', className)} {...rest} />
}

export interface TdProps extends TdHTMLAttributes<HTMLTableCellElement> {
  /** Right-align with tabular figures. */
  numeric?: boolean
  /** Allow wrapping (cells are nowrap by default, as in the DS). */
  wrap?: boolean
  /** Shrink to content (checkbox and action columns). */
  shrink?: boolean
}

export function Td({ numeric, wrap, shrink, className, ...rest }: TdProps) {
  return (
    <td
      className={cx(
        'cgz-table__td',
        numeric && 'cgz-table__cell--numeric',
        wrap && 'cgz-table__cell--wrap',
        shrink && 'cgz-table__cell--shrink',
        className,
      )}
      {...rest}
    />
  )
}
