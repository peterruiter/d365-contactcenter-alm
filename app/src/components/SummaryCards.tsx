import { Card, Text } from '@fluentui/react-components'
import type { DiffSummary } from '../types/alm'

const CARDS: { key: keyof DiffSummary; label: string }[] = [
  { key: 'missingInTarget', label: 'Missing in target' },
  { key: 'changed', label: 'Changed' },
  { key: 'extraInTarget', label: 'Extra in target' },
  { key: 'equal', label: 'Equal' },
]

export function SummaryCards({ summary }: { summary: DiffSummary }) {
  return (
    <div className="cards">
      {CARDS.map((c) => (
        <Card key={c.key} appearance="outline">
          <Text size={700} weight="semibold">
            {summary[c.key]}
          </Text>
          <Text size={200}>{c.label}</Text>
        </Card>
      ))}
    </div>
  )
}
