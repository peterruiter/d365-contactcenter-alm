import { ArrowRightRegular, ArrowSwapRegular } from '@fluentui/react-icons'
import { Button, IconButton, Panel, Select, Tag } from '../../ui'
import type { Migration } from '../../hooks/useMigration'
import { relativeTime } from './labels'

/** Step 1: choose where configuration comes from and where it goes. */
export function EnvironmentPicker({ m }: { m: Migration }) {
  const options = m.environments.map((e) => ({ value: e.id, label: e.name }))
  const sources = m.environments.filter((e) => e.role !== 'target').map((e) => ({ value: e.id, label: e.name }))
  const targets = m.environments.filter((e) => e.role !== 'source').map((e) => ({ value: e.id, label: e.name }))
  const same = !!m.sourceId && m.sourceId === m.targetId
  const loading = m.busy === 'environments'

  return (
    <Panel
      title="Environments"
      description="Configuration is read from the source and written to the target. Nothing is written until you apply a plan."
    >
      <div className="env-picker">
        <Select
          label="Source"
          hint={m.source?.url}
          value={m.sourceId ?? ''}
          placeholder={loading ? 'Loading environments…' : 'Select a source environment'}
          options={sources.length ? sources : options}
          onChange={(e) => m.setSource(e.target.value)}
          disabled={loading || m.busy === 'compare'}
        />
        <IconButton
          className="env-picker__swap"
          label="Swap source and target"
          icon={<ArrowSwapRegular />}
          variant="secondary"
          onClick={m.swap}
          disabled={!m.sourceId || !m.targetId || m.busy === 'compare'}
        />
        <Select
          label="Target"
          hint={m.target?.url}
          error={same ? 'Pick a different environment from the source.' : undefined}
          value={m.targetId ?? ''}
          placeholder={loading ? 'Loading environments…' : 'Select a target environment'}
          options={targets.length ? targets : options}
          onChange={(e) => m.setTarget(e.target.value)}
          disabled={loading || m.busy === 'compare'}
        />
        <Button
          icon
          busy={m.busy === 'compare'}
          disabled={!m.sourceId || !m.targetId || same || loading}
          onClick={() => void m.compare()}
        >
          {m.busy === 'compare' ? 'Comparing' : m.diff ? 'Compare again' : 'Compare'}
        </Button>
      </div>
      <div className="row env-picker__meta">
        {m.target?.requireApproval && <Tag quiet>{m.target.name} needs approval to apply</Tag>}
        {m.diff && (
          <span className="muted t-body-small">
            Last compared {relativeTime(m.diff.generated)}
          </span>
        )}
        {m.busy === 'compare' && (
          <span className="muted t-body-small">
            Reading both environments. This takes 10 to 30 seconds.
          </span>
        )}
      </div>
    </Panel>
  )
}

/** Compact "Dev → Test" line shown once a compare exists. */
export function EnvironmentSummary({ m }: { m: Migration }) {
  return (
    <div className="env-summary">
      <span className="env-summary__name">{m.source?.name}</span>
      <span className="env-summary__arrow" aria-label="to">
        <ArrowRightRegular fontSize={20} />
      </span>
      <span className="env-summary__name">{m.target?.name}</span>
      {m.target?.requireApproval && <Tag quiet>Approval required</Tag>}
    </div>
  )
}
