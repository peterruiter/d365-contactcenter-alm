import { Badge, Text } from '@fluentui/react-components'
import type { Plan, PlanOperation } from '../types/alm'

function groupByStage(ops: PlanOperation[]): Map<number, PlanOperation[]> {
  const map = new Map<number, PlanOperation[]>()
  for (const op of ops) {
    const list = map.get(op.stage) ?? []
    list.push(op)
    map.set(op.stage, list)
  }
  return new Map([...map.entries()].sort((a, b) => a[0] - b[0]))
}

export function PlanPanel({ plan }: { plan: Plan }) {
  const stages = groupByStage(plan.operations)

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
      {[...stages.entries()].map(([stage, ops]) => (
        <div key={stage} style={{ marginBottom: 16 }}>
          <Text weight="semibold" block style={{ marginBottom: 4 }}>
            Stage {stage}
          </Text>
          {ops.map((op) => (
            <div key={op.seq} className="stage-row">
              <Badge appearance="tint" color={op.op === 'create' ? 'success' : op.op === 'update' ? 'warning' : 'informative'}>
                {op.op}
              </Badge>
              <Text style={{ flex: 1 }}>{op.matchKey}</Text>
              <Text size={200} style={{ color: 'var(--colorNeutralForeground3)' }}>{op.label}</Text>
            </div>
          ))}
        </div>
      ))}
    </div>
  )
}
