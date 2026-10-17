import { Notice, StatusLabel } from '../../ui'
import type { RunVerification } from '../../types/alm'
import { fullName, plural } from './labels'

const STATUS_TEXT: Record<string, string> = {
  Changed: 'Still differs',
  Missing: 'Not found',
  Ambiguous: 'Ambiguous',
  NotFound: 'Not found',
}

/** After an apply: did every written record end up the same as in the source? */
export function VerificationPanel({ v, targetName }: { v: RunVerification; targetName: string }) {
  if (v.state === 'Error') {
    return (
      <Notice tone="warning" title="The check afterwards did not run" live="none">
        {v.message ?? 'Compare again to see whether the target matches the source.'} The writes themselves stand.
      </Notice>
    )
  }

  const explained = v.differences.every((d) => d.status === 'Changed' && d.fields.length > 0 && d.fields.every((f) => f.note))
  return (
    <section className="stack stack--tight" aria-labelledby="verify-title">
      {v.state === 'Verified' ? (
        <Notice tone="success" title={`Checked: ${targetName} matches the source`} live="none">
          {v.checked === 1
            ? 'The record this run wrote was read back from the target and is the same as in the source.'
            : `All ${v.checked} records this run wrote were read back from the target and are the same as in the source.`}
        </Notice>
      ) : (
        <Notice tone={explained ? 'info' : 'warning'} title={`Checked: ${plural(v.differences.length, 'record')} still differ${v.differences.length === 1 ? 's' : ''}`} live="none">
          {v.matched} of {v.checked} written records are the same as in the source.{' '}
          {explained
            ? 'Dataverse does not let the rest be set the way the source has them; each is explained below.'
            : 'Look at the ones below in the target; comparing again shows them too.'}
        </Notice>
      )}

      {v.differences.length > 0 && (
        <ul className="items tbl__body" id="verify-title" aria-label="Records that still differ">
          {v.differences.map((d, i) => (
            <li className="item" key={`${d.table}-${i}`}>
              <StatusLabel kind={d.status === 'Changed' ? 'changed' : 'failed'}>{STATUS_TEXT[d.status] ?? d.status}</StatusLabel>
              <div>
                <div className="rec__name">{fullName(d.displayName, d.context)}</div>
                <div className="item__msg">
                  {d.tableLabel} · {d.message}
                </div>
                {d.fields.length > 0 && (
                  <ul className="verify-fields">
                    {d.fields.map((f, j) => (
                      <li key={j}>
                        <span className="verify-fields__label">{f.label}</span>{' '}
                        <span className="muted">source</span> {f.source || '(empty)'} <span className="muted">· target</span> {f.target || '(empty)'}
                        {f.note && <div className="muted t-body-small">{f.note}</div>}
                      </li>
                    ))}
                  </ul>
                )}
              </div>
            </li>
          ))}
        </ul>
      )}

      {v.added.length > 0 && (
        <Notice tone="info" title={`${plural(v.added.length, 'record')} appeared in ${targetName} during the run`} live="none">
          Dataverse created {v.added.length === 1 ? 'it' : 'them'} on its own (it provisions routing for some new workstreams). {v.added.length === 1 ? 'It is' : 'They are'} not in the source:
          <ul className="rail-list" style={{ marginTop: 'var(--space-2)' }}>
            {v.added.map((a, i) => (
              <li key={i}>
                {a.tableLabel}: {fullName(a.displayName, a.context)}
              </li>
            ))}
          </ul>
        </Notice>
      )}
    </section>
  )
}
