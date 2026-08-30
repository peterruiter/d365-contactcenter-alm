import type { CSSProperties } from 'react'
import type { DiffSummary } from '../types/alm'
import { brand } from '../brands'

// Green/orange/grey are diff-status semantics, stable across brands (see theme.ts). "Equal"
// has no inherent semantic color of its own, so it takes the active brand's primary instead
// of a hardcoded Capgemini blue.
const CARDS: { key: keyof DiffSummary; label: string; accent: string }[] = [
  { key: 'missingInTarget', label: 'Missing in target', accent: '#4eb972' }, // Zodiak Green-600
  { key: 'changed', label: 'Changed', accent: '#f68f40' }, // Zodiak Orange-500
  { key: 'extraInTarget', label: 'Extra in target', accent: '#a6acb5' }, // Zodiak Neutral-400
  { key: 'equal', label: 'Equal', accent: brand.colors.primary },
]

export function SummaryCards({ summary }: { summary: DiffSummary }) {
  return (
    <div className="cards">
      {CARDS.map((c) => (
        <div key={c.key} className="stat" style={{ '--stat-accent': c.accent } as CSSProperties}>
          <div className="stat-num">{summary[c.key]}</div>
          <div className="stat-label">{c.label}</div>
        </div>
      ))}
    </div>
  )
}
