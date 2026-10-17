import { Notice, Spinner, StatusDot } from '../../ui'
import type { CheckDefinition, CheckResult } from '../../services/localSetup'

interface Props {
  definitions: CheckDefinition[]
  results: Record<string, CheckResult | undefined>
  runningId: string | null
}

const KIND = { pass: 'done', warn: 'blocked', fail: 'failed' } as const

export function CheckList({ definitions, results, runningId }: Props) {
  return (
    <ol className="check-list">
      {definitions.map((d, i) => {
        const r = results[d.id]
        const running = runningId === d.id
        return (
          <li key={d.id} className={`check-row${r?.status === 'fail' && !running ? ' check-row--fail' : ''}`}>
            <span className="check-row__marker">
              {running ? (
                <Spinner size="sm" label={`Checking ${d.title}`} />
              ) : r ? (
                <StatusDot kind={KIND[r.status]} label={r.status === 'pass' ? 'Passed' : r.status === 'warn' ? 'Warning' : 'Failed'} />
              ) : (
                <span className="muted t-body-small">{i + 1}</span>
              )}
            </span>
            <div>
              <div className="check-row__title">{d.title}</div>
              <div className="check-row__summary">{running ? 'Checking…' : r ? r.summary : d.description}</div>
              {r && !running && r.detail.length > 0 && (
                <ul className="check-row__detail">
                  {r.detail.map((line, j) => (
                    <li key={j}>{line}</li>
                  ))}
                </ul>
              )}
              {r && !running && r.fix && r.status !== 'pass' && (
                <Notice tone={r.status === 'fail' ? 'error' : 'warning'} live="none" style={{ marginTop: 'var(--space-3)' }}>
                  {r.fix}
                </Notice>
              )}
            </div>
          </li>
        )
      })}
    </ol>
  )
}
