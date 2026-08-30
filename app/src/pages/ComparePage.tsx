import { useMemo, useState } from 'react'
import {
  Button,
  MessageBar,
  MessageBarBody,
  Switch,
  Text,
} from '@fluentui/react-components'
import { ArrowUndoRegular, PlayRegular, ClipboardTaskListLtrRegular } from '@fluentui/react-icons'
import { useAlmFlow } from '../hooks/useAlmFlow'
import { EnvironmentBar } from '../components/EnvironmentBar'
import { SummaryCards } from '../components/SummaryCards'
import { DiffTable } from '../components/DiffTable'
import { DetectOnlyPanel } from '../components/DetectOnlyPanel'
import { PlanPanel } from '../components/PlanPanel'
import { RunProgress } from '../components/RunProgress'
import { ApplyDialog } from '../components/ApplyDialog'
import { WizardSteps } from '../components/WizardSteps'
import type { RecordDiff, SelectionItem, TableDiff } from '../types/alm'

export function ComparePage() {
  const flow = useAlmFlow()
  const [showEqual, setShowEqual] = useState(false)
  const [selected, setSelected] = useState<Set<string>>(new Set())
  const [applyOpen, setApplyOpen] = useState(false)

  const target = flow.environments.find((e) => e.id === flow.targetId)

  // Flat lookup of every record in the diff, keyed "table|matchKey", so a selection can walk
  // dependsOn edges without re-scanning the whole diff each time.
  const recordByKey = useMemo(() => {
    const m = new Map<string, RecordDiff>()
    if (flow.diff) {
      for (const t of flow.diff.tables) {
        for (const r of t.records) m.set(`${t.table}|${r.matchKey}`, r)
      }
    }
    return m
  }, [flow.diff])

  // A record plus every dependency (transitively) that still needs to move. A dependency already
  // equal in the target is left alone; there is nothing to select.
  const withDependencies = (startKey: string): string[] => {
    const out: string[] = []
    const seen = new Set<string>()
    const stack = [startKey]
    while (stack.length > 0) {
      const k = stack.pop() as string
      if (seen.has(k)) continue
      seen.add(k)
      out.push(k)
      const rec = recordByKey.get(k)
      for (const dep of rec?.dependsOn ?? []) {
        const depKey = `${dep.table}|${dep.matchKey}`
        const depRec = recordByKey.get(depKey)
        if (depRec && (depRec.status === 'MissingInTarget' || depRec.status === 'Changed')) {
          stack.push(depKey)
        }
      }
    }
    return out
  }

  const toggle = (table: string, matchKey: string) => {
    const k = `${table}|${matchKey}`
    setSelected((prev) => {
      const next = new Set(prev)
      if (next.has(k)) {
        next.delete(k)
      } else {
        for (const key of withDependencies(k)) next.add(key)
      }
      return next
    })
  }

  const toggleTable = (t: TableDiff, on: boolean) => {
    setSelected((prev) => {
      const next = new Set(prev)
      for (const r of t.records) {
        if (r.status !== 'MissingInTarget' && r.status !== 'Changed') continue
        const k = `${t.table}|${r.matchKey}`
        if (on) {
          for (const key of withDependencies(k)) next.add(key)
        } else {
          next.delete(k)
        }
      }
      return next
    })
  }

  const movableCount = useMemo(() => {
    if (!flow.diff) return 0
    return flow.diff.tables.reduce(
      (n, t) => n + t.records.filter((r) => r.status === 'MissingInTarget' || r.status === 'Changed').length,
      0,
    )
  }, [flow.diff])

  const buildPlan = () => {
    const selection: SelectionItem[] | undefined =
      selected.size === 0
        ? undefined
        : [...selected].map((k) => {
            // matchKey itself often contains '|' (composite match keys), so split only on the
            // first one - the table's logical name never does.
            const i = k.indexOf('|')
            return { table: k.slice(0, i), matchKey: k.slice(i + 1) }
          })
    flow.buildPlan(selection)
  }

  const runFrom = (mode: 'dryRun' | 'apply', approved: boolean) => {
    setApplyOpen(false)
    flow.apply(mode, approved)
  }

  return (
    <div className="layout">
      <div className="layout-main">
      <div className="section panel">
        <EnvironmentBar
          environments={flow.environments}
          sourceId={flow.sourceId}
          targetId={flow.targetId}
          busy={flow.busy}
          onSource={flow.setSource}
          onTarget={flow.setTarget}
          onCompare={() => flow.compare()}
        />
      </div>

      {flow.error && (
        <MessageBar intent="error" className="section">
          <MessageBarBody>{flow.error}</MessageBarBody>
        </MessageBar>
      )}

      {flow.diff && (
        <>
          <div className="section">
            <SummaryCards summary={flow.diff.summary} />
          </div>

          <DetectOnlyPanel findings={flow.diff.detectOnly} />

          <div className="section panel">
            <div className="section-head">
              <span className="section-title">Differences</span>
              <Switch
                checked={showEqual}
                onChange={(_, d) => setShowEqual(d.checked)}
                label="Show equal"
              />
            </div>
            <DiffTable
              diff={flow.diff}
              showEqual={showEqual}
              selected={selected}
              onToggle={toggle}
              onToggleTable={toggleTable}
            />
            <div className="actions">
              <Button
                appearance="primary"
                icon={<ClipboardTaskListLtrRegular />}
                disabled={flow.busy || movableCount === 0}
                onClick={buildPlan}
              >
                Build plan{selected.size > 0 ? ` (${selected.size} selected)` : ` (all ${movableCount})`}
              </Button>
              <Text size={200} style={{ color: 'var(--colorNeutralForeground3)' }}>
                Leave nothing selected to plan everything movable.
              </Text>
            </div>
          </div>
        </>
      )}

      {flow.plan && (
        <>
          <div className="section panel">
            <div className="section-head">
              <span className="section-title">Plan</span>
            </div>
            <PlanPanel plan={flow.plan} />
            {flow.plan.operations.length > 0 && (
              <div className="actions">
                <Button
                  appearance="primary"
                  icon={<PlayRegular />}
                  disabled={flow.busy}
                  onClick={() => setApplyOpen(true)}
                >
                  Run
                </Button>
              </div>
            )}
          </div>
          <ApplyDialog
            open={applyOpen}
            plan={flow.plan}
            target={target}
            busy={flow.busy}
            onClose={() => setApplyOpen(false)}
            onRun={runFrom}
          />
        </>
      )}

      {flow.run && (
        <>
          <div className="section panel">
            <div className="section-head">
              <span className="section-title">Run</span>
            </div>
            <RunProgress run={flow.run} />
            {flow.run.mode === 'apply' && flow.run.state !== 'RolledBack' && (
              <div className="actions">
                <Button
                  appearance="secondary"
                  icon={<ArrowUndoRegular />}
                  disabled={flow.busy}
                  onClick={flow.rollback}
                >
                  Roll back this run
                </Button>
              </div>
            )}
          </div>
        </>
      )}
      </div>

      <WizardSteps flow={flow} movableCount={movableCount} />
    </div>
  )
}
