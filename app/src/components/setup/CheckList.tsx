import { MessageBar, MessageBarBody, Spinner } from '@fluentui/react-components'
import { CheckmarkCircleFilled, CircleRegular, ErrorCircleFilled, WarningFilled } from '@fluentui/react-icons'
import type { CheckDefinition, CheckResult } from '../../services/localSetup'

interface Props {
  definitions: CheckDefinition[]
  results: Record<string, CheckResult | undefined>
  runningId: string | null
}

function Marker({ result, running, index }: { result?: CheckResult; running: boolean; index: number }) {
  if (running) return <Spinner size="tiny" />
  if (result?.status === 'pass') return <CheckmarkCircleFilled className="wiz-icon wiz-icon-done" />
  if (result?.status === 'warn') return <WarningFilled className="wiz-icon wiz-icon-warning" />
  if (result?.status === 'fail') return <ErrorCircleFilled className="wiz-icon wiz-icon-error" />
  return (
    <span className="wiz-step-num">
      <CircleRegular className="wiz-icon wiz-icon-pending" />
      <span>{index + 1}</span>
    </span>
  )
}

export function CheckList({ definitions, results, runningId }: Props) {
  return (
    <ol className="check-list">
      {definitions.map((d, i) => {
        const r = results[d.id]
        const running = runningId === d.id
        return (
          <li key={d.id} className={`check-row check-${running ? 'running' : (r?.status ?? 'pending')}`}>
            <span className="check-marker">
              <Marker result={r} running={running} index={i} />
            </span>
            <div className="check-body">
              <div className="check-title">{d.title}</div>
              <div className="check-desc">{running ? 'Checking…' : r ? r.summary : d.description}</div>
              {r && !running && r.detail.length > 0 && (
                <ul className="check-detail">
                  {r.detail.map((line, j) => (
                    <li key={j}>{line}</li>
                  ))}
                </ul>
              )}
              {r && !running && r.fix && r.status !== 'pass' && (
                <MessageBar intent={r.status === 'fail' ? 'error' : 'warning'} className="check-fix">
                  <MessageBarBody>{r.fix}</MessageBarBody>
                </MessageBar>
              )}
            </div>
          </li>
        )
      })}
    </ol>
  )
}
