import { useEffect, useState } from 'react'
import { Button, Checkbox, Dialog, KeyValue, Notice } from '../../ui'
import type { Migration } from '../../hooks/useMigration'
import { plural } from './labels'

/** The last stop before writing to an environment. */
export function ApplyDialog({ m, open, onClose }: { m: Migration; open: boolean; onClose: () => void }) {
  const [approved, setApproved] = useState(false)
  useEffect(() => {
    if (open) setApproved(false)
  }, [open])
  const plan = m.plan
  if (!plan) return null
  const s = plan.summary
  const needsApproval = !!m.target?.requireApproval
  const dry = m.dryRun

  return (
    <Dialog
      open={open}
      onClose={onClose}
      title={`Apply to ${m.target?.name ?? 'the target'}`}
      description="This writes to the environment. Records it changes are snapshotted first, and records it creates are noted, so the run can be rolled back."
      actions={
        <>
          <Button variant="secondary" onClick={onClose}>
            Cancel
          </Button>
          <Button
            busy={m.busy === 'apply'}
            disabled={(needsApproval && !approved) || m.busy !== null}
            onClick={async () => {
              await m.execute('apply', approved)
              onClose()
            }}
          >
            Apply {plural(s.ready, 'record')}
          </Button>
        </>
      }
    >
      <div className="stack stack--tight">
        <KeyValue
          compact
          items={[
            { label: 'From', value: m.source?.name ?? plan.source },
            { label: 'To', value: m.target?.name ?? plan.target },
            { label: 'New records', value: s.creates },
            { label: 'Updated records', value: s.updates },
            { label: 'Links set at the end', value: s.links },
            { label: 'Blocked, left out', value: s.blocked },
          ]}
        />
        {dry && dry.state !== 'Succeeded' && (
          <Notice tone="warning" live="none">
            The dry run reported {plural(dry.summary.failed + dry.summary.skipped + dry.summary.blocked, 'problem')}. Those records will not be written.
          </Notice>
        )}
        {needsApproval && (
          <Checkbox
            label={`This change to ${m.target?.name} has been approved`}
            hint="Required for this environment."
            checked={approved}
            onChange={(e) => setApproved(e.target.checked)}
          />
        )}
      </div>
    </Dialog>
  )
}
