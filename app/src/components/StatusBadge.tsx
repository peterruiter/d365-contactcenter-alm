import { statusColor } from '../theme'
import type { RecordStatus } from '../types/alm'

export function StatusBadge({ status }: { status: RecordStatus }) {
  const c = statusColor[status]
  return (
    <span
      className="badge"
      style={{
        color: c.fg,
        background: c.bg === 'transparent' ? 'transparent' : c.bg,
        border: c.bg === 'transparent' ? `1px solid ${c.dot}` : 'none',
      }}
    >
      <span className="badge-dot" style={{ background: c.dot }} />
      {c.label}
    </span>
  )
}
