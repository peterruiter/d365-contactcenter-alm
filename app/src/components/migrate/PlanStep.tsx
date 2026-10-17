import { useId, useMemo, useState } from 'react'
import { AddRegular, ChevronDownRegular, ChevronUpRegular, DismissRegular } from '@fluentui/react-icons'
import { Button, Notice, Panel, StatusDot, StatusLabel, Switch, Tag } from '../../ui'
import { refOf, type Migration } from '../../hooks/useMigration'
import type { PlanOperation } from '../../types/alm'
import { ApplyDialog } from './ApplyDialog'
import { DEP_STATE, OP_LABEL, plural } from './labels'

/** Step 3: the plan, checked before anything runs. */
export function PlanStep({ m }: { m: Migration }) {
  const plan = m.plan
  const [applyOpen, setApplyOpen] = useState(false)
  const fixes = useMemo(
    () => (plan?.operations ?? []).flatMap((o) => o.blockers.map((b) => b.fix).filter(Boolean)),
    [plan],
  )
  if (!plan) return null
  const s = plan.summary
  const busy = m.busy !== null
  const dryRanThisPlan = !!m.dryRun

  return (
    <div className="workspace">
      <div className="stack">
        {s.blocked > 0 ? (
          <Notice
            tone="error"
            title={`${plural(s.blocked, 'record')} cannot be moved yet`}
            actions={
              fixes.length > 0 ? (
                <Button size="sm" leadingIcon={<AddRegular />} busy={m.busy === 'plan'} disabled={busy} onClick={() => void m.applyAllFixes()}>
                  Add {plural(new Set(fixes.map((f) => `${f?.table}|${f?.matchKey}`)).size, 'needed record')}
                </Button>
              ) : undefined
            }
          >
            Each one says why below. Blocked records are left out of a run; everything else still moves.
          </Notice>
        ) : (
          <Notice tone="success" title="Every record in the plan can be moved" live="none">
            {s.links > 0
              ? `${plural(s.links, 'link')} to records written later in the run will be set at the end. `
              : ''}
            Run a dry run to go through every write without changing {m.target?.name ?? 'the target'}.
          </Notice>
        )}

        {plan.ignored.length > 0 && (
          <Notice tone="info" title={`${plural(plan.ignored.length, 'selected record')} will not be moved`} live="none">
            <ul className="rail-list">
              {plan.ignored.map((i) => (
                <li key={`${i.table}|${i.matchKey}`}>
                  <strong className="rail-list__title">{i.displayName}</strong>: {i.reason}
                </li>
              ))}
            </ul>
          </Notice>
        )}

        {plan.stages.map((st) => {
          const ops = plan.operations.filter((o) => o.stage === st.stage)
          if (!ops.length) return null
          return (
            <section className="stage" key={st.stage} aria-labelledby={`st-${st.stage}`}>
              <div className="stage__head">
                <span className="stage__num" aria-hidden="true">{st.stage}</span>
                <h2 className="stage__title" id={`st-${st.stage}`}>{st.label}</h2>
                {st.description && <span className="stage__desc">{st.description}</span>}
              </div>
              <div className="tbl__body" role="list">
                {ops.map((o) => (
                  <OperationRow key={o.seq} m={m} op={o} />
                ))}
              </div>
            </section>
          )
        })}
      </div>

      <aside className="rail" aria-label="Plan check">
        <Panel title="Plan check" titleAs="h2">
          <div className="stack stack--tight">
            <div className="stats">
              <div className="stat">
                <span className="stat__num">{s.ready}</span>
                <span className="stat__label"><StatusDot kind="ready" /> ready</span>
              </div>
              <div className="stat">
                <span className="stat__num">{s.blocked}</span>
                <span className="stat__label"><StatusDot kind="blocked" /> blocked</span>
              </div>
            </div>
            <ul className="rail-list">
              <li className="row row--between"><span>New records</span><span>{s.creates}</span></li>
              <li className="row row--between"><span>Updated records</span><span>{s.updates}</span></li>
              <li className="row row--between"><span>Added because needed</span><span>{s.autoIncluded}</span></li>
              <li className="row row--between"><span>Links set at the end</span><span>{s.links}</span></li>
            </ul>
            <Switch checked={m.includeDependencies} onChange={m.setIncludeDependencies} label="Add the records they need" disabled={busy} />
            <div className="rail-actions">
              <Button busy={m.busy === 'dryRun'} disabled={busy || s.ready === 0} onClick={() => void m.execute('dryRun', false)}>
                Dry run
              </Button>
              <Button variant="secondary" disabled={busy || !dryRanThisPlan || s.ready === 0} onClick={() => setApplyOpen(true)}>
                Apply to {m.target?.name ?? 'target'}
              </Button>
              <p className="muted t-body-small">
                {dryRanThisPlan
                  ? 'The dry run of this plan has run. Apply writes it for real; changed records are snapshotted first so the run can be rolled back.'
                  : 'Apply unlocks after a dry run of this plan. A dry run changes nothing.'}
              </p>
              <Button size="sm" variant="secondary" disabled={busy} onClick={() => m.setStep('review')}>
                Back to the differences
              </Button>
            </div>
          </div>
        </Panel>
      </aside>

      <ApplyDialog m={m} open={applyOpen} onClose={() => setApplyOpen(false)} />
    </div>
  )
}

function OperationRow({ m, op: o }: { m: Migration; op: PlanOperation }) {
  const [open, setOpen] = useState(false)
  const detailId = useId()
  const blocked = o.status === 'blocked'
  const missing = o.dependencies.filter((d) => d.state === 'missing').length
  const canRemove = !o.autoIncluded && m.selected.has(refOf(o.table, o.matchKey))

  return (
    <div className="rec" role="listitem">
      <div className="rec__line">
        <StatusDot kind={blocked ? 'blocked' : 'ready'} label={blocked ? 'Blocked' : 'Ready'} />
        <div className="rec__main">
          <div className="row" style={{ gap: 'var(--space-2)' }}>
            <span className="op__kind">{OP_LABEL[o.op]}</span>
            <span className="rec__name">{o.displayName}</span>
          </div>
          <div className="rec__context">
            {o.tableLabel}
            {o.context ? ` · ${o.context}` : ''}
          </div>
        </div>
        <div className="rec__meta">
          {o.autoIncluded && <Tag quiet title={`Needed by ${o.neededBy.join(', ')}`}>Added: needed</Tag>}
          {o.dependencies.length > 0 && (
            <span className="muted t-body-small nowrap">
              {missing ? `${missing} of ${o.dependencies.length} needs missing` : plural(o.dependencies.length, 'need') + ' met'}
            </span>
          )}
          {blocked && <StatusLabel kind="blocked" />}
          <button type="button" className="rec__toggle" aria-expanded={open} aria-controls={detailId} onClick={() => setOpen((x) => !x)}>
            {open ? 'Hide' : 'Details'}
            {open ? <ChevronUpRegular fontSize={16} /> : <ChevronDownRegular fontSize={16} />}
          </button>
        </div>
      </div>

      {(blocked || open) && (
        <div className="rec__detail" id={detailId}>
          {blocked && (
            <div className="blockers">
              {o.blockers.map((b, i) => (
                <Notice
                  key={i}
                  tone="error"
                  live="none"
                  actions={
                    b.fix ? (
                      <Button size="sm" variant="secondary" leadingIcon={<AddRegular />} disabled={m.busy !== null} onClick={() => b.fix && void m.applyFix(b.fix)}>
                        {b.fix.label}
                      </Button>
                    ) : undefined
                  }
                >
                  {b.message}
                </Notice>
              ))}
            </div>
          )}
          {open && (
            <>
              {o.autoIncluded && o.neededBy.length > 0 && (
                <p className="t-body-small">Added to the plan because {o.neededBy.join(', ')} {o.neededBy.length === 1 ? 'needs' : 'need'} it.</p>
              )}
              {o.changes.length > 0 && (
                <div>
                  <div className="subhead">Settings that change</div>
                  <p className="t-body-small">{o.changes.join(', ')}</p>
                </div>
              )}
              {o.dependencies.length > 0 && (
                <div>
                  <div className="subhead">Needs</div>
                  <ul className="deps">
                    {o.dependencies.map((d) => (
                      <li key={`${d.table}|${d.matchKey}|${d.via}`}>
                        <StatusDot kind={DEP_STATE[d.state].kind} label={DEP_STATE[d.state].label} />
                        <span>
                          {d.label} <span className="deps__via">· {d.via} · {DEP_STATE[d.state].label.toLowerCase()}</span>
                        </span>
                      </li>
                    ))}
                  </ul>
                </div>
              )}
              {o.warnings.length > 0 && (
                <Notice tone="warning" live="none">
                  {o.warnings.join(' ')}
                </Notice>
              )}
              {canRemove && (
                <div>
                  <Button size="sm" variant="secondary" leadingIcon={<DismissRegular />} disabled={m.busy !== null} onClick={() => void m.dropFromPlan([refOf(o.table, o.matchKey)])}>
                    Leave out of this plan
                  </Button>
                </div>
              )}
            </>
          )}
        </div>
      )}
    </div>
  )
}
