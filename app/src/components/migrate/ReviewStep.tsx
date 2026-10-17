import { useId, useMemo, useState } from 'react'
import { ChevronDownRegular, ChevronUpRegular, TextBulletListTreeRegular } from '@fluentui/react-icons'
import {
  Badge,
  Button,
  Checkbox,
  EmptyState,
  FilterChips,
  Notice,
  Panel,
  SearchInput,
  StatusDot,
  StatusLabel,
  Switch,
  Table,
  TBody,
  Td,
  Th,
  THead,
  Tr,
  useToast,
} from '../../ui'
import { isMovable, refOf, type Migration } from '../../hooks/useMigration'
import type { RecordDiff, RecordStatus, TableDiff } from '../../types/alm'
import { fullName, plural, RECORD_STATUS } from './labels'

const STATUS_ORDER: RecordStatus[] = ['MissingInTarget', 'Changed', 'Ambiguous', 'ExtraInTarget', 'Equal']

/** Step 2: what differs, and what to move. */
export function ReviewStep({ m }: { m: Migration }) {
  const diff = m.diff
  const [statuses, setStatuses] = useState<string[]>(['MissingInTarget', 'Changed', 'Ambiguous'])
  const [query, setQuery] = useState('')

  const counts = useMemo(() => {
    const c: Record<string, number> = {}
    for (const t of diff?.tables ?? []) for (const r of t.records) c[r.status] = (c[r.status] ?? 0) + 1
    return c
  }, [diff])

  const groups = useMemo(() => {
    if (!diff) return []
    const q = query.trim().toLowerCase()
    const match = (t: TableDiff, r: RecordDiff) =>
      statuses.includes(r.status) &&
      (!q || `${r.displayName} ${r.context ?? ''} ${t.label}`.toLowerCase().includes(q))
    const byGroup = new Map<string, Array<{ table: TableDiff; records: RecordDiff[] }>>()
    for (const t of [...diff.tables].sort((a, b) => a.stage - b.stage)) {
      const records = t.records
        .filter((r) => match(t, r))
        .sort((a, b) => STATUS_ORDER.indexOf(a.status) - STATUS_ORDER.indexOf(b.status) || fullName(a.displayName, a.context).localeCompare(fullName(b.displayName, b.context)))
      if (!records.length) continue
      const g = byGroup.get(t.group) ?? []
      g.push({ table: t, records })
      byGroup.set(t.group, g)
    }
    return [...byGroup.entries()]
  }, [diff, statuses, query])

  if (!diff) return null

  const movableRefs = diff.tables.flatMap((t) => t.records.filter(isMovable).map((r) => refOf(t.table, r.matchKey)))
  const selectedCount = movableRefs.filter((r) => m.selected.has(r)).length
  const needed = new Set<string>()
  for (const ref of m.selected) {
    for (const d of m.recordByRef.get(ref)?.record.dependsOn ?? []) {
      const dRef = refOf(d.table, d.matchKey)
      if (m.recordByRef.get(dRef)?.record.status === 'MissingInTarget' && !m.selected.has(dRef)) needed.add(dRef)
    }
  }
  const nothingToMove = movableRefs.length === 0

  return (
    <div className="workspace">
      <div className="stack">
        {diff.notices.length > 0 && (
          <Notice tone="warning" title="Differences between the two environments' versions" live="none">
            <ul className="rail-list">
              {diff.notices.map((n, i) => (
                <li key={i}>{n.message}</li>
              ))}
            </ul>
          </Notice>
        )}

        <div>
          <div className="toolbar">
            <div className="toolbar__search">
              <SearchInput label="Find a record" value={query} onChange={setQuery} placeholder="Name, parent or table" size="sm" />
            </div>
            <FilterChips
              aria-label="Show records that are"
              items={STATUS_ORDER.map((s) => ({ id: s, label: RECORD_STATUS[s].label, count: counts[s] ?? 0, disabled: !counts[s] }))}
              selected={statuses}
              onChange={setStatuses}
            />
          </div>

          {groups.length === 0 ? (
            <EmptyState title={nothingToMove ? 'The target already matches the source' : 'Nothing matches these filters'}>
              {nothingToMove
                ? 'Every record that this tool moves is the same in both environments.'
                : 'Change the filters or the search to see more records.'}
            </EmptyState>
          ) : (
            groups.map(([group, tables]) => (
              <section className="group" key={group} aria-labelledby={`g-${group}`}>
                <div className="group__head">
                  <h2 className="group__title" id={`g-${group}`}>{group}</h2>
                  <span className="muted t-body-small">{plural(tables.reduce((n, t) => n + t.records.length, 0), 'record')}</span>
                </div>
                {tables.map(({ table, records }) => (
                  <TableBlock key={table.table} m={m} table={table} records={records} />
                ))}
              </section>
            ))
          )}
        </div>
      </div>

      <aside className="rail" aria-label="Selection">
        <Panel title="What moves" titleAs="h2">
          <div className="stack stack--tight">
            <div className="stats">
              <div className="stat">
                <span className="stat__num">{selectedCount}</span>
                <span className="stat__label">of {movableRefs.length} selected</span>
              </div>
              <div className="stat">
                <span className="stat__num">{needed.size}</span>
                <span className="stat__label">needed by them</span>
              </div>
            </div>
            <ul className="rail-list">
              {STATUS_ORDER.filter((s) => counts[s]).map((s) => (
                <li key={s} className="row row--between">
                  <StatusLabel kind={RECORD_STATUS[s].kind}>{RECORD_STATUS[s].label}</StatusLabel>
                  <span>{counts[s]}</span>
                </li>
              ))}
            </ul>
            <Switch
              checked={m.includeDependencies}
              onChange={m.setIncludeDependencies}
              label="Add the records they need"
            />
            <p className="muted t-body-small">
              {m.includeDependencies
                ? needed.size
                  ? `${plural(needed.size, 'record')} the selection needs will be added to the plan.`
                  : 'Anything the selection needs that is missing in the target is added to the plan.'
                : 'Records whose dependencies are missing in the target will be blocked in the plan.'}
            </p>
            <div className="rail-actions">
              <Button icon busy={m.busy === 'plan'} disabled={selectedCount === 0} onClick={() => void m.buildPlan()}>
                Check the plan
              </Button>
              <div className="row">
                <Button size="sm" variant="secondary" onClick={() => m.setMany(movableRefs, true)} disabled={selectedCount === movableRefs.length}>
                  Select all
                </Button>
                <Button size="sm" variant="secondary" onClick={() => m.setMany(movableRefs, false)} disabled={selectedCount === 0}>
                  Clear
                </Button>
              </div>
            </div>
          </div>
        </Panel>

        {diff.detectOnly.length > 0 && (
          <Panel title="Set up by hand in the target" titleAs="h2" description="These cannot move as data. The rest of the record moves; do these steps after.">
            <ul className="rail-list">
              {diff.detectOnly.map((d, i) => (
                <li key={i}>
                  <div className="rail-list__title">{d.record}</div>
                  <div className="muted">{d.label}. {d.message}</div>
                </li>
              ))}
            </ul>
          </Panel>
        )}
      </aside>
    </div>
  )
}

function TableBlock({ m, table, records }: { m: Migration; table: TableDiff; records: RecordDiff[] }) {
  const movable = records.filter(isMovable).map((r) => refOf(table.table, r.matchKey))
  const on = movable.filter((r) => m.selected.has(r)).length
  return (
    <div className="tbl">
      <div className="tbl__head">
        {movable.length > 0 ? (
          <Checkbox
            label={`Select all ${table.label.toLowerCase()}`}
            hideLabel
            checked={on === movable.length}
            indeterminate={on > 0 && on < movable.length}
            onChange={(e) => m.setMany(movable, e.target.checked)}
          />
        ) : (
          <span style={{ width: 17 }} />
        )}
        <span className="tbl__title grow">{table.label}</span>
        <Badge>{records.length}</Badge>
      </div>
      <div className="tbl__body" role="list">
        {records.map((r) => (
          <RecordRow key={r.matchKey} m={m} table={table} record={r} />
        ))}
      </div>
    </div>
  )
}

function RecordRow({ m, table, record: r }: { m: Migration; table: TableDiff; record: RecordDiff }) {
  const [open, setOpen] = useState(false)
  const { toast } = useToast()
  const ref = refOf(table.table, r.matchKey)
  const movable = isMovable(r)
  // Everything under this record (and what that uses), not counting the record itself.
  const bundle = useMemo(() => (r.status === 'ExtraInTarget' || r.status === 'Ambiguous' ? [] : m.bundleOf(ref).filter((x) => x !== ref)), [m, ref, r.status])
  const bundleUnselected = bundle.filter((x) => !m.selected.has(x)).length
  const selectAll = () => {
    const added = m.selectBundle(ref)
    toast({
      tone: 'success',
      title: `${r.displayName} and everything under it`,
      message: added ? `${plural(added, 'record')} added to the selection.` : 'All of it was already selected.',
    })
  }
  const st = RECORD_STATUS[r.status]
  const missingDeps = r.dependsOn.filter((d) => m.recordByRef.get(refOf(d.table, d.matchKey))?.record.status === 'MissingInTarget')
  const hasDetail = r.fields.length > 0 || r.dependsOn.length > 0 || !!r.note || bundle.length > 0
  const detailId = useId()

  return (
    <div className="rec" role="listitem">
      <div className="rec__line">
        {movable ? (
          <Checkbox label={`Move ${fullName(r.displayName, r.context)}`} hideLabel checked={m.selected.has(ref)} onChange={() => m.toggle(ref)} />
        ) : (
          <span aria-hidden="true" />
        )}
        <div className="rec__main">
          <div className="rec__name">{r.displayName}</div>
          {r.context && <div className="rec__context">{r.context}</div>}
        </div>
        <div className="rec__meta">
          {r.fields.length > 0 && <span className="muted t-body-small nowrap">{plural(r.fields.length, 'setting')}</span>}
          {missingDeps.length > 0 && (
            <span className="muted t-body-small nowrap" title={missingDeps.map((d) => d.label).join('\n')}>
              needs {plural(missingDeps.length, 'new record')}
            </span>
          )}
          {bundle.length > 0 && (
            <button
              type="button"
              className="rec__toggle"
              onClick={selectAll}
              title={`Select ${r.displayName} with the ${plural(bundle.length, 'record')} under it and the ones they use`}
              aria-label={`Select ${fullName(r.displayName, r.context)} with everything under it: ${plural(bundle.length, 'record')}`}
            >
              <TextBulletListTreeRegular fontSize={16} />
              With everything under it ({bundle.length}){bundleUnselected === 0 ? ' ✓' : ''}
            </button>
          )}
          <StatusLabel kind={st.kind} title={st.hint}>{st.label}</StatusLabel>
          {hasDetail && (
            <button type="button" className="rec__toggle" aria-expanded={open} aria-controls={detailId} onClick={() => setOpen((o) => !o)}>
              {open ? 'Hide' : 'Details'}
              {open ? <ChevronUpRegular fontSize={16} /> : <ChevronDownRegular fontSize={16} />}
            </button>
          )}
        </div>
      </div>
      {open && (
        <div className="rec__detail" id={detailId}>
          {r.note && (
            <Notice tone="warning" live="none">
              {r.note}
            </Notice>
          )}
          {r.fields.length > 0 && (
            <div>
              <div className="subhead">What changes in {m.target?.name ?? 'the target'}</div>
              <Table caption={`Settings that differ for ${r.displayName}`} className="delta">
                <THead>
                  <Tr noHover>
                    <Th>Setting</Th>
                    <Th>{m.target?.name ?? 'Target'} now</Th>
                    <Th>After moving</Th>
                  </Tr>
                </THead>
                <TBody>
                  {r.fields.map((f) => (
                    <Tr key={f.name} noHover>
                      <Td wrap>{f.label}</Td>
                      {f.kind === 'definition' ? (
                        <Td wrap colSpan={2}>
                          <span className="delta__new">The rules differ: {f.source}</span>
                        </Td>
                      ) : (
                        <>
                          <Td wrap>
                            <span className="delta__old">{f.target ?? '(empty)'}</span>
                          </Td>
                          <Td wrap>
                            <span className="delta__new">{f.source ?? '(empty)'}</span>
                          </Td>
                        </>
                      )}
                    </Tr>
                  ))}
                </TBody>
              </Table>
            </div>
          )}
          {bundle.length > 0 && (
            <div>
              <div className="subhead">Under it, and what that uses ({bundle.length})</div>
              <ul className="deps">
                {bundle.slice(0, 15).map((b) => {
                  const e = m.recordByRef.get(b)
                  if (!e) return null
                  const k = RECORD_STATUS[e.record.status]
                  return (
                    <li key={b}>
                      <StatusDot kind={k.kind} label={k.label} />
                      <span>
                        {fullName(e.record.displayName, e.record.context)} <span className="deps__via">· {e.table.label}{m.selected.has(b) ? ' · selected' : ''}</span>
                      </span>
                    </li>
                  )
                })}
              </ul>
              {bundle.length > 15 && <p className="muted t-body-small">and {bundle.length - 15} more.</p>}
              <div style={{ marginTop: 'var(--space-3)' }}>
                <Button size="sm" variant="secondary" leadingIcon={<TextBulletListTreeRegular />} disabled={bundleUnselected === 0} onClick={selectAll}>
                  {bundleUnselected === 0 ? 'All selected' : `Select all ${bundle.length + (movable ? 1 : 0)}`}
                </Button>
              </div>
            </div>
          )}
          {r.dependsOn.length > 0 && (
            <div>
              <div className="subhead">Needs in {m.target?.name ?? 'the target'}</div>
              <ul className="deps">
                {r.dependsOn.map((d) => {
                  const dRec = m.recordByRef.get(refOf(d.table, d.matchKey))?.record
                  const isNew = dRec?.status === 'MissingInTarget'
                  const selected = m.selected.has(refOf(d.table, d.matchKey))
                  return (
                    <li key={`${d.table}|${d.matchKey}|${d.via}`}>
                      <StatusDot kind={isNew ? (selected ? 'ready' : 'new') : 'done'} label={isNew ? 'New' : 'In the target'} />
                      <span>
                        {d.label} <span className="deps__via">· {d.via}</span>
                        {isNew && (
                          <span className="deps__via">
                            {' '}· {selected ? 'selected' : m.includeDependencies ? 'will be added' : 'not selected'}
                          </span>
                        )}
                        {d.deferred && <span className="deps__via"> · linked at the end</span>}
                      </span>
                    </li>
                  )
                })}
              </ul>
            </div>
          )}
        </div>
      )}
    </div>
  )
}
