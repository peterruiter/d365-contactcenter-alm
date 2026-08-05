import { Badge, MessageBar, MessageBarBody, Text } from '@fluentui/react-components'
import { CheckmarkCircleFilled, ErrorCircleFilled, ClockRegular } from '@fluentui/react-icons'
import type { Run, StageState } from '../types/alm'

function stageIcon(state: StageState) {
  if (state === 'Succeeded') return <CheckmarkCircleFilled style={{ color: 'var(--colorPaletteGreenForeground1)' }} />
  if (state === 'Failed') return <ErrorCircleFilled style={{ color: 'var(--colorPaletteRedForeground1)' }} />
  return <ClockRegular style={{ color: 'var(--colorNeutralForeground3)' }} />
}

const RUN_COLOR: Record<string, 'success' | 'danger' | 'warning' | 'informative'> = {
  Succeeded: 'success',
  Failed: 'danger',
  PartiallyFailed: 'warning',
  RolledBack: 'informative',
  Running: 'informative',
  Queued: 'informative',
}

export function RunProgress({ run }: { run: Run }) {
  return (
    <div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 12 }}>
        <Badge appearance="filled" color={RUN_COLOR[run.state] ?? 'informative'}>
          {run.state}
        </Badge>
        <Text size={200} style={{ color: 'var(--colorNeutralForeground3)' }}>
          {run.mode === 'dryRun' ? 'Dry run, nothing written' : 'Applied to target'}
          {run.snapshotId ? ` · snapshot ${run.snapshotId}` : ''}
        </Text>
      </div>

      {run.stages.map((s) => (
        <div key={s.stage} className="stage-row">
          {stageIcon(s.state)}
          <Text weight="semibold" style={{ minWidth: 60 }}>Stage {s.stage}</Text>
          <Text style={{ flex: 1 }}>{s.label}</Text>
          <Text size={200} style={{ color: 'var(--colorNeutralForeground3)' }}>{s.written} written</Text>
        </div>
      ))}

      {run.stages.flatMap((s) => s.warnings).length > 0 && (
        <div style={{ marginTop: 12, display: 'flex', flexDirection: 'column', gap: 8 }}>
          {run.stages.flatMap((s) => s.warnings).map((w, i) => (
            <MessageBar key={i} intent="warning">
              <MessageBarBody>{w}</MessageBarBody>
            </MessageBar>
          ))}
        </div>
      )}

      {run.problems.length > 0 && (
        <div style={{ marginTop: 12, display: 'flex', flexDirection: 'column', gap: 8 }}>
          {run.problems.map((p, i) => (
            <MessageBar key={i} intent="error">
              <MessageBarBody>{p}</MessageBarBody>
            </MessageBar>
          ))}
        </div>
      )}
    </div>
  )
}
