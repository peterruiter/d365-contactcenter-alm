import { statusColor } from '../theme'
import type { RecordStatus } from '../types/alm'

export function StatusBadge({ status }: { status: RecordStatus }) {
  const c = statusColor[status]
  return (
    <span
      style={{
        display: 'inline-block',
        padding: '2px 8px',
        borderRadius: 4,
        fontSize: 12,
        fontWeight: 600,
        color: c.fg,
        background: c.bg === 'transparent' ? undefined : c.bg,
        border: c.bg === 'transparent' ? `1px solid ${c.fg}33` : 'none',
        whiteSpace: 'nowrap',
      }}
    >
      {c.label}
    </span>
  )
}
