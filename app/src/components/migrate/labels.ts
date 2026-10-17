import type { StatusKind } from '../../ui'
import type { DependencyState, ItemOutcome, OpKind, RecordStatus, RunState } from '../../types/alm'

// One vocabulary for the whole app: what a status is called and which dot it gets.

export const RECORD_STATUS: Record<RecordStatus, { label: string; kind: StatusKind; hint: string }> = {
  MissingInTarget: { label: 'New', kind: 'new', hint: 'Only in the source. Moving it creates it in the target.' },
  Changed: { label: 'Changed', kind: 'changed', hint: 'In both, with different settings. Moving it updates the target.' },
  ExtraInTarget: { label: 'Only in target', kind: 'extra', hint: 'Only in the target. Left as it is.' },
  Equal: { label: 'Same', kind: 'same', hint: 'Identical in both. Nothing to do.' },
  Ambiguous: { label: 'Ambiguous', kind: 'blocked', hint: 'Matches more than one record, so it cannot be paired.' },
}

export const OP_LABEL: Record<OpKind | 'link', string> = {
  create: 'Create',
  update: 'Update',
  'skip-existing': 'Keep',
  link: 'Link',
}

export const DEP_STATE: Record<DependencyState, { label: string; kind: StatusKind }> = {
  inTarget: { label: 'Already in the target', kind: 'done' },
  createdEarlier: { label: 'Created earlier in this run', kind: 'ready' },
  linkedLater: { label: 'Linked at the end of the run', kind: 'ready' },
  missing: { label: 'Missing', kind: 'blocked' },
}

export const OUTCOME: Record<ItemOutcome, { label: string; kind: StatusKind }> = {
  created: { label: 'Created', kind: 'done' },
  updated: { label: 'Updated', kind: 'done' },
  linked: { label: 'Linked', kind: 'done' },
  unchanged: { label: 'Kept', kind: 'skipped' },
  wouldCreate: { label: 'Would create', kind: 'ready' },
  wouldUpdate: { label: 'Would update', kind: 'ready' },
  wouldLink: { label: 'Would link', kind: 'ready' },
  skipped: { label: 'Skipped', kind: 'skipped' },
  blocked: { label: 'Blocked', kind: 'blocked' },
  failed: { label: 'Failed', kind: 'failed' },
}

export const RUN_STATE: Record<RunState, { label: string; kind: StatusKind }> = {
  Succeeded: { label: 'Succeeded', kind: 'done' },
  PartiallyFailed: { label: 'Finished with problems', kind: 'blocked' },
  Failed: { label: 'Failed', kind: 'failed' },
  RolledBack: { label: 'Rolled back', kind: 'skipped' },
}

export const isProblem = (o: ItemOutcome) => o === 'failed' || o === 'blocked' || o === 'skipped'

export function plural(n: number, one: string, many = `${one}s`) {
  return `${n} ${n === 1 ? one : many}`
}

export function fullName(displayName: string, context?: string | null) {
  return context ? `${context} › ${displayName}` : displayName
}

export function relativeTime(iso?: string) {
  if (!iso) return ''
  const s = Math.round((Date.now() - new Date(iso).getTime()) / 1000)
  if (s < 45) return 'just now'
  if (s < 3600) return `${Math.round(s / 60)} min ago`
  if (s < 86400) return `${Math.round(s / 3600)} h ago`
  return new Date(iso).toLocaleString()
}
