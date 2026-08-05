import {
  Accordion,
  AccordionHeader,
  AccordionItem,
  AccordionPanel,
  Checkbox,
  Text,
} from '@fluentui/react-components'
import { StatusBadge } from './StatusBadge'
import type { DiffModel, RecordDiff, TableDiff } from '../types/alm'

interface Props {
  diff: DiffModel
  showEqual: boolean
  selected: Set<string>
  onToggle: (table: string, matchKey: string) => void
  onToggleTable: (table: TableDiff, on: boolean) => void
}

function key(table: string, matchKey: string): string {
  return `${table}|${matchKey}`
}

function selectable(r: RecordDiff): boolean {
  return r.status === 'MissingInTarget' || r.status === 'Changed'
}

function counts(t: TableDiff) {
  const movable = t.records.filter(selectable).length
  const total = t.records.length
  return { movable, total }
}

export function DiffTable({ diff, showEqual, selected, onToggle, onToggleTable }: Props) {
  const tables = diff.tables
    .map((t) => ({
      ...t,
      records: showEqual ? t.records : t.records.filter((r) => r.status !== 'Equal'),
    }))
    .filter((t) => t.records.length > 0)

  const openItems = tables
    .filter((t) => t.records.some(selectable))
    .map((t) => t.table)

  return (
    <Accordion multiple collapsible defaultOpenItems={openItems}>
      {tables.map((t) => {
        const c = counts(t)
        const tableSelected = t.records.filter(selectable)
        const allOn = tableSelected.length > 0 && tableSelected.every((r) => selected.has(key(t.table, r.matchKey)))
        const someOn = tableSelected.some((r) => selected.has(key(t.table, r.matchKey)))

        return (
          <AccordionItem key={t.table} value={t.table} className="table-group">
            <AccordionHeader>
              <Text weight="semibold">{t.label}</Text>
              <Text size={200} style={{ marginLeft: 8, color: 'var(--colorNeutralForeground3)' }}>
                {c.movable} to move / {c.total} shown
              </Text>
            </AccordionHeader>
            <AccordionPanel>
              {tableSelected.length > 0 && (
                <div style={{ padding: '4px 0 8px' }}>
                  <Checkbox
                    label="Select all movable in this table"
                    checked={allOn ? true : someOn ? 'mixed' : false}
                    onChange={(_, d) => onToggleTable(t, d.checked === true)}
                  />
                </div>
              )}
              <table style={{ width: '100%', borderCollapse: 'collapse' }}>
                <tbody>
                  {t.records.map((r) => (
                    <tr key={r.matchKey} style={{ borderTop: '1px solid var(--colorNeutralStroke3)' }}>
                      <td style={{ width: 28, padding: '6px 4px', verticalAlign: 'top' }}>
                        {selectable(r) && (
                          <Checkbox
                            checked={selected.has(key(t.table, r.matchKey))}
                            onChange={() => onToggle(t.table, r.matchKey)}
                            aria-label={`Move ${r.matchKey}`}
                          />
                        )}
                      </td>
                      <td style={{ padding: '6px 4px', verticalAlign: 'top' }}>
                        <Text>{r.matchKey}</Text>
                        {r.fields.length > 0 && (
                          <div style={{ marginTop: 4 }}>
                            {r.fields.map((f) => (
                              <div key={f.name} className="field-delta">
                                {f.name}: <span style={{ color: 'var(--colorPaletteRedForeground1)' }}>{f.target ?? '-'}</span>
                                {' -> '}
                                <span style={{ color: 'var(--colorPaletteGreenForeground1)' }}>{f.source ?? '-'}</span>
                              </div>
                            ))}
                          </div>
                        )}
                      </td>
                      <td style={{ padding: '6px 4px', verticalAlign: 'top', textAlign: 'right', width: 130 }}>
                        <StatusBadge status={r.status} />
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </AccordionPanel>
          </AccordionItem>
        )
      })}
    </Accordion>
  )
}
