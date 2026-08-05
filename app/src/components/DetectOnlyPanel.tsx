import { MessageBar, MessageBarBody, MessageBarTitle, Text } from '@fluentui/react-components'
import type { DetectFinding } from '../types/alm'

const TYPE_TITLE: Record<string, string> = {
  phoneNumber: 'Phone number',
  voiceBot: 'Copilot Studio agent',
  channelAccount: 'Channel account',
  survey: 'Customer Voice survey',
  eventGrid: 'Event Grid subscription',
}

export function DetectOnlyPanel({ findings }: { findings: DetectFinding[] }) {
  if (findings.length === 0) return null
  return (
    <div className="section">
      <Text size={400} weight="semibold" block style={{ marginBottom: 8 }}>
        Provision in target ({findings.length})
      </Text>
      <Text size={200} block style={{ marginBottom: 12, color: 'var(--colorNeutralForeground3)' }}>
        These are per-environment. The tool detects them and leaves them alone. Set them up in the target.
      </Text>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
        {findings.map((f, i) => (
          <MessageBar key={i} intent="warning">
            <MessageBarBody>
              <MessageBarTitle>{TYPE_TITLE[f.type] ?? f.type}: {f.record}</MessageBarTitle>
              {f.message}
            </MessageBarBody>
          </MessageBar>
        ))}
      </div>
    </div>
  )
}
