import { Badge, Text } from '@fluentui/react-components'
import { CheckmarkCircleRegular } from '@fluentui/react-icons'
import type { Plan } from '../types/alm'

export function PlanPanel({ plan }: { plan: Plan }) {
  if (plan.operations.length === 0) {
    return (
      <div className="empty">
        <Text weight="semibold">Nothing to move</Text>
        <Text size={200}>The target already matches the source for what you selected.</Text>
      </div>
    )
  }

  return (
    <div>
      <Text size={200} block style={{ marginBottom: 12, color: 'var(--colorNeutralForeground3)' }}>
        {plan.operations.length} operations, written in this order. Parents land before the records that point at them.
      </Text>
      {plan.stages.map((s) => (
        <div key={s.stage} style={{ marginBottom: 16 }}>
          <Text weight="semibold" block style={{ marginBottom: 4 }}>
            Stage {s.stage}: {s.label}
          </Text>
          {s.operations.length === 0 ? (
            <div className="stage-row stage-row-empty">
              <CheckmarkCircleRegular style={{ color: 'var(--colorNeutralForeground3)' }} />
              <Text size={200} style={{ color: 'var(--colorNeutralForeground3)' }}>Nothing to move in this stage</Text>
            </div>
          ) : (
            s.operations.map((op) => (
              <div key={op.seq} className="stage-row">
                <Badge appearance="tint" color={op.op === 'create' ? 'success' : op.op === 'update' ? 'warning' : 'informative'}>
                  {op.op}
                </Badge>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <Text style={{ overflowWrap: 'anywhere' }}>{op.displayName || op.matchKey}</Text>
                  {op.displayName && <div className="match-key-hint">{op.matchKey}</div>}
                </div>
                <Text size={200} style={{ color: 'var(--colorNeutralForeground3)' }}>{op.label}</Text>
              </div>
            ))
          )}
        </div>
      ))}
    </div>
  )
}
