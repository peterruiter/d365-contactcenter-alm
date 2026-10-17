import { useEffect, useState } from 'react'
import { Button, Dialog, EmptyState, Panel, StatusLabel, Table, TBody, Td, Th, THead, Tr } from '../ui'
import { getAlmService } from '../services'
import type { EnvironmentRef, Run, RunListItem } from '../types/alm'
import { fullName, isProblem, OUTCOME, plural, RUN_STATE } from '../components/migrate/labels'

/** Recent runs, newest first, with what each one did. */
export function HistoryPage({ runs, environments, onRefresh }: { runs: RunListItem[]; environments: EnvironmentRef[]; onRefresh: () => Promise<void> }) {
  const [open, setOpen] = useState<Run | null>(null)
  const [error, setError] = useState<string | null>(null)
  const name = (id: string) => environments.find((e) => e.id === id)?.name ?? id

  useEffect(() => {
    void onRefresh()
  }, [onRefresh])

  const show = async (id: string) => {
    setError(null)
    try {
      setOpen(await getAlmService().getRun(id))
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    }
  }

  return (
    <div className="stack">
      <div className="page-head">
        <div>
          <h1 className="t-h2">Run history</h1>
          <p className="page-head__lead">Dry runs and applies from this machine, newest first.</p>
        </div>
        <Button size="sm" variant="secondary" onClick={() => void onRefresh()}>
          Refresh
        </Button>
      </div>
      {error && <p className="muted">{error}</p>}
      <Panel flush>
        {runs.length === 0 ? (
          <EmptyState title="No runs yet">A dry run or an apply shows up here.</EmptyState>
        ) : (
          <Table caption="Runs">
            <THead>
              <Tr noHover>
                <Th>When</Th>
                <Th>From and to</Th>
                <Th>Kind</Th>
                <Th>Result</Th>
                <Th>Records</Th>
              </Tr>
            </THead>
            <TBody>
              {runs.map((r) => (
                <Tr key={r.runId} className="history-row" onClick={() => void show(r.runId)}>
                  <Td wrap>
                    <button type="button" className="rec__toggle" onClick={(e) => { e.stopPropagation(); void show(r.runId) }}>
                      {r.startedAt ? new Date(r.startedAt).toLocaleString() : r.runId}
                    </button>
                  </Td>
                  <Td>{name(r.source)} to {name(r.target)}</Td>
                  <Td>{r.mode === 'dryRun' || r.mode === 'DryRun' ? 'Dry run' : 'Apply'}</Td>
                  <Td><StatusLabel kind={RUN_STATE[r.state]?.kind ?? 'skipped'}>{RUN_STATE[r.state]?.label ?? r.state}</StatusLabel></Td>
                  <Td>
                    {r.summary ? `${r.summary.created} new, ${r.summary.updated} updated${r.summary.failed ? `, ${r.summary.failed} failed` : ''}` : ''}
                  </Td>
                </Tr>
              ))}
            </TBody>
          </Table>
        )}
      </Panel>

      <Dialog
        open={!!open}
        onClose={() => setOpen(null)}
        title={open ? `${open.mode === 'dryRun' ? 'Dry run' : 'Apply'}: ${name(open.source)} to ${name(open.target)}` : ''}
        description={open?.finishedAt ? new Date(open.finishedAt).toLocaleString() : undefined}
        actions={<Button variant="secondary" onClick={() => setOpen(null)}>Close</Button>}
      >
        {open && (
          <div className="stack stack--tight">
            <StatusLabel kind={RUN_STATE[open.state].kind} size="md">{RUN_STATE[open.state].label}</StatusLabel>
            <p>
              {plural(open.summary.created, 'record')} created, {plural(open.summary.updated, 'record')} updated,{' '}
              {plural(open.summary.linked, 'link')} set, {open.summary.failed} failed.
            </p>
            {open.stages.flatMap((s) => s.items).filter((i) => isProblem(i.outcome)).length > 0 && (
              <ul className="rail-list">
                {open.stages.flatMap((s) => s.items).filter((i) => isProblem(i.outcome)).map((i, idx) => (
                  <li key={idx}>
                    <StatusLabel kind={OUTCOME[i.outcome].kind}>{OUTCOME[i.outcome].label}</StatusLabel>{' '}
                    <span className="rail-list__title">{fullName(i.displayName, i.context)}</span>: {i.message}
                  </li>
                ))}
              </ul>
            )}
          </div>
        )}
      </Dialog>
    </div>
  )
}
