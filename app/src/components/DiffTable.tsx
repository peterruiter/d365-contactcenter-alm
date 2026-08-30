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
  const labelByTable = Object.fromEntries(diff.tables.map((t) => [t.table, t.label]))
  const statusByKey = new Map<string, RecordDiff['status']>()
  const displayNameByKey = new Map<string, string>()
  for (const t of diff.tables) {
    for (const r of t.records) {
      statusByKey.set(`${t.table}|${r.matchKey}`, r.status)
      if (r.displayName) displayNameByKey.set(`${t.table}|${r.matchKey}`, r.displayName)
    }
  }
  // Dependencies still missing or changed in the target: selecting this record needs these too.
  function unmetDependencies(r: RecordDiff) {
    return r.dependsOn.filter((d) => {
      const s = statusByKey.get(`${d.table}|${d.matchKey}`)
      return s === 'MissingInTarget' || s === 'Changed'
    })
  }

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
              <div>
                {t.records.map((r) => {
                  const deps = unmetDependencies(r)
                  return (
                    <div key={r.matchKey} className="diff-row">
                      <div>
                        {selectable(r) && (
                          <Checkbox
                            checked={selected.has(key(t.table, r.matchKey))}
                            onChange={() => onToggle(t.table, r.matchKey)}
                            aria-label={`Move ${r.displayName || r.matchKey}`}
                          />
                        )}
                      </div>
                      <div>
                        <Text weight="medium">{r.displayName || r.matchKey}</Text>
                        {r.displayName && (
                          <div className="match-key-hint">{r.matchKey}</div>
                        )}
                        {r.fields.length > 0 && (
                          <div style={{ marginTop: 2 }}>
                            {r.fields.map((f) => (
                              <div key={f.name} className="field-delta">
                                <span style={{ color: 'var(--colorNeutralForeground3)' }}>{f.name}: </span>
                                <span style={{ color: 'var(--colorPaletteRedForeground1)' }}>{f.target ?? '-'}</span>
                                {' \u2192 '}
                                <span style={{ color: 'var(--colorPaletteGreenForeground1)' }}>{f.source ?? '-'}</span>
                              </div>
                            ))}
                          </div>
                        )}
                        {deps.length > 0 && (
                          <div className="dep-hint">
                            Requires{' '}
                            {deps
                              .map((d) => {
                                const name = displayNameByKey.get(`${d.table}|${d.matchKey}`) ?? d.matchKey
                                return `${labelByTable[d.table] ?? d.table}: ${name}`
                              })
                              .join(', ')}
                            {' \u2014 selected automatically with this row.'}
                          </div>
                        )}
                      </div>
                      <div style={{ justifySelf: 'end' }}>
                        <StatusBadge status={r.status} />
                      </div>
                    </div>
                  )
                })}
              </div>
            </AccordionPanel>
          </AccordionItem>
        )
      })}
    </Accordion>
  )
}
