import type { CSSProperties } from 'react'
import type { DiffSummary } from '../types/alm'

const CARDS: { key: keyof DiffSummary; label: string; accent: string }[] = [
  { key: 'missingInTarget', label: 'Missing in target', accent: '#1a9e4b' },
  { key: 'changed', label: 'Changed', accent: '#e08600' },
  { key: 'extraInTarget', label: 'Extra in target', accent: '#8a97a8' },
  { key: 'equal', label: 'Equal', accent: '#0070ad' },
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
