import {
  Dialog,
  DialogSurface,
  DialogTitle,
  DialogBody,
  DialogContent,
  DialogActions,
  Button,
  Checkbox,
  Text,
} from '@fluentui/react-components'
import { useState } from 'react'
import type { EnvironmentRef, Plan } from '../types/alm'

interface Props {
  open: boolean
  plan: Plan
  target: EnvironmentRef | undefined
  busy: boolean
  onClose: () => void
  onRun: (mode: 'dryRun' | 'apply', approved: boolean) => void
}

export function ApplyDialog({ open, plan, target, busy, onClose, onRun }: Props) {
  const [approved, setApproved] = useState(false)
  const needsApproval = !!target?.requireApproval
  const canApply = !needsApproval || approved

  return (
    <Dialog open={open} onOpenChange={(_, d) => !d.open && onClose()}>
      <DialogSurface>
        <DialogBody>
          <DialogTitle>Write to {target?.name ?? 'target'}</DialogTitle>
          <DialogContent>
            <Text block style={{ marginBottom: 12 }}>
              {plan.operations.length} operations will run against {target?.name}. Dry run first if you have not.
            </Text>
            {needsApproval && (
              <Checkbox
                checked={approved}
                onChange={(_, d) => setApproved(d.checked === true)}
                label={`I approve this change to ${target?.name}`}
              />
            )}
          </DialogContent>
          <DialogActions>
            <Button appearance="secondary" disabled={busy} onClick={() => onRun('dryRun', false)}>
              Dry run
            </Button>
            <Button appearance="primary" disabled={busy || !canApply} onClick={() => onRun('apply', approved)}>
              Apply
            </Button>
            <Button appearance="subtle" disabled={busy} onClick={onClose}>
              Cancel
            </Button>
          </DialogActions>
        </DialogBody>
      </DialogSurface>
    </Dialog>
  )
}
