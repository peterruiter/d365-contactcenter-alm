import { Dropdown, Option, Button, Spinner } from '@fluentui/react-components'
import { ArrowRightRegular, ArrowSyncRegular } from '@fluentui/react-icons'
import type { EnvironmentRef } from '../types/alm'

interface Props {
  environments: EnvironmentRef[]
  sourceId: string | null
  targetId: string | null
  busy: boolean
  onSource: (id: string) => void
  onTarget: (id: string) => void
  onCompare: () => void
}

export function EnvironmentBar({
  environments, sourceId, targetId, busy,
  onSource, onTarget, onCompare,
}: Props) {
  const source = environments.find((e) => e.id === sourceId)
  const target = environments.find((e) => e.id === targetId)
  const canCompare = !!sourceId && !!targetId && sourceId !== targetId && !busy

  const optionList = environments.map((e) => (
    <Option key={e.id} value={e.id} text={e.name}>
      {e.name}
    </Option>
  ))

  return (
    <div className="env-grid">
      <span className="eg-label eg-src-label">Source</span>
      <div className="eg-src-ctl">
        <Dropdown
          placeholder="Pick source"
          value={source?.name ?? ''}
          selectedOptions={sourceId ? [sourceId] : []}
          onOptionSelect={(_, d) => d.optionValue && onSource(d.optionValue)}
        >
          {optionList}
        </Dropdown>
      </div>
      <span className="eg-hint eg-src-hint">Read from here</span>

      <div className="eg-arrow">
        <ArrowRightRegular fontSize={22} />
      </div>

      <span className="eg-label eg-tgt-label">Target</span>
      <div className="eg-tgt-ctl">
        <Dropdown
          placeholder="Pick target"
          value={target?.name ?? ''}
          selectedOptions={targetId ? [targetId] : []}
          onOptionSelect={(_, d) => d.optionValue && onTarget(d.optionValue)}
        >
          {optionList}
        </Dropdown>
      </div>
      <span className="eg-hint eg-tgt-hint">
        Write to here
        {target?.requireApproval && <span className="pill">Approval required</span>}
      </span>

      <Button
        className="eg-btn"
        appearance="primary"
        size="medium"
        icon={busy ? <Spinner size="tiny" /> : <ArrowSyncRegular />}
        disabled={!canCompare}
        onClick={onCompare}
      >
        Compare
      </Button>
    </div>
  )
}
