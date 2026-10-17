import type { DiffModel, Plan, Run } from '../types/alm'

// The backend is PowerShell, which can send an empty list as null and a one-item list as a bare
// object. The backend is fixed and tested for that (tests/Contract.Tests.ps1); this makes sure a
// response that still slips through shows as data instead of crashing a page on .length or .map.

export function list<T>(value: T[] | T | null | undefined): T[] {
  if (value === null || value === undefined) return []
  return Array.isArray(value) ? value : [value]
}

export function normaliseDiff(d: DiffModel): DiffModel {
  return {
    ...d,
    tables: list(d.tables).map((t) => ({
      ...t,
      records: list(t.records).map((r) => ({ ...r, fields: list(r.fields), dependsOn: list(r.dependsOn) })),
    })),
    detectOnly: list(d.detectOnly),
    notices: list(d.notices),
  }
}

export function normalisePlan(p: Plan): Plan {
  return {
    ...p,
    operations: list(p.operations).map((o) => ({
      ...o,
      dependencies: list(o.dependencies),
      blockers: list(o.blockers),
      warnings: list(o.warnings),
      neededBy: list(o.neededBy),
      changes: list(o.changes),
    })),
    ignored: list(p.ignored),
    stages: list(p.stages),
  }
}

export function normaliseRun(r: Run): Run {
  return {
    ...r,
    stages: list(r.stages).map((s) => ({ ...s, items: list(s.items), warnings: list(s.warnings) })),
    problems: list(r.problems),
    cleanup: r.cleanup ? { ...r.cleanup, unresolved: list(r.cleanup.unresolved) } : r.cleanup,
    verification: r.verification
      ? {
          ...r.verification,
          differences: list(r.verification.differences).map((d) => ({ ...d, fields: list(d.fields) })),
          added: list(r.verification.added),
        }
      : r.verification,
  }
}
