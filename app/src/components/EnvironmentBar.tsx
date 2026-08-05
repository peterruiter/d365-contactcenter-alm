import { Dropdown, Option, Button, Field, Spinner } from '@fluentui/react-components'
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

function envLabel(env: EnvironmentRef): string {
  return env.requireApproval ? `${env.name} (approval)` : env.name
}

export function EnvironmentBar({ environments, sourceId, targetId, busy, onSource, onTarget, onCompare }: Props) {
  const source = environments.find((e) => e.id === sourceId)
  const target = environments.find((e) => e.id === targetId)
  const canCompare = !!sourceId && !!targetId && sourceId !== targetId && !busy

  return (
    <div className="env-bar">
      <Field label="Source" hint="Read from here">
        <Dropdown
          placeholder="Pick source"
          value={source ? envLabel(source) : ''}
          selectedOptions={sourceId ? [sourceId] : []}
          onOptionSelect={(_, d) => d.optionValue && onSource(d.optionValue)}
          style={{ minWidth: 200 }}
        >
          {environments.map((e) => (
            <Option key={e.id} value={e.id} text={envLabel(e)}>
              {envLabel(e)}
            </Option>
          ))}
        </Dropdown>
      </Field>

      <ArrowRightRegular className="env-arrow" fontSize={24} />

      <Field label="Target" hint="Write to here" validationMessage={target?.requireApproval ? 'Needs approval to apply' : undefined} validationState={target?.requireApproval ? 'warning' : 'none'}>
        <Dropdown
          placeholder="Pick target"
          value={target ? envLabel(target) : ''}
          selectedOptions={targetId ? [targetId] : []}
          onOptionSelect={(_, d) => d.optionValue && onTarget(d.optionValue)}
          style={{ minWidth: 200 }}
        >
          {environments.map((e) => (
            <Option key={e.id} value={e.id} text={envLabel(e)}>
              {envLabel(e)}
            </Option>
          ))}
        </Dropdown>
      </Field>

      <Button
        appearance="primary"
        icon={busy ? <Spinner size="tiny" /> : <ArrowSyncRegular />}
        disabled={!canCompare}
        onClick={onCompare}
      >
        Compare
      </Button>
    </div>
  )
}
