import { useMemo, useState } from 'react'
import { Button, Dropdown, Field, Input, Option, Spinner, Switch } from '@fluentui/react-components'
import { ArrowRightRegular, DeleteRegular } from '@fluentui/react-icons'
import type { EnvRole } from '../../types/alm'
import type { EnvironmentInput, SetupEnvironment } from '../../services/localSetup'

const GUID = /^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$/i

export function slugify(name: string): string {
  return name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 40)
}

interface Props {
  /** null when adding a new environment. */
  existing: SetupEnvironment | null
  /** Saved environments, for "same app registration as". */
  others: SetupEnvironment[]
  takenIds: string[]
  busy: boolean
  onSave: (id: string, input: EnvironmentInput) => void
  onDelete?: () => void
}

const roleLabels: Record<EnvRole, string> = {
  any: 'Source or target',
  source: 'Source only',
  target: 'Target only',
}

export function EnvironmentForm({ existing, others, takenIds, busy, onSave, onDelete }: Props) {
  const [name, setName] = useState(existing?.name ?? '')
  const [url, setUrl] = useState(existing?.url ?? '')
  const [tenantId, setTenantId] = useState(existing?.tenantId ?? '')
  const [clientId, setClientId] = useState(existing?.clientId ?? '')
  const [secret, setSecret] = useState('')
  const [sameAs, setSameAs] = useState('')
  const [role, setRole] = useState<EnvRole>(existing?.role ?? 'any')
  const [requireApproval, setRequireApproval] = useState(existing?.requireApproval ?? false)

  const id = existing?.id ?? slugify(name)
  const sameAsEnv = others.find((o) => o.id === sameAs)
  const reusable = others.filter((o) => o.hasSecret && o.id !== existing?.id)

  const problems = useMemo(() => {
    const p: Record<string, string> = {}
    const u = url.trim().replace(/\/$/, '')
    if (!name.trim()) p.name = 'Give it a name, e.g. "Contoso Dev".'
    else if (!existing && !id) p.name = 'Use at least one letter or digit.'
    else if (!existing && takenIds.includes(id)) p.name = `There is already an environment with id "${id}".`
    if (!u) p.url = 'Required.'
    else if (!/^https:\/\/[a-z0-9.-]+$/i.test(u)) p.url = 'Just the host, e.g. https://contoso-dev.crm4.dynamics.com - no path.'
    if (!tenantId.trim()) p.tenantId = 'Required.'
    if (!GUID.test(clientId.trim())) p.clientId = 'A GUID: Application (client) ID on the app registration Overview page.'
    if (!sameAs && !secret && !existing?.hasSecret) p.secret = 'Required.'
    return p
  }, [name, url, tenantId, clientId, secret, sameAs, existing, id, takenIds])

  const urlHint =
    url && !problems.url && !/\.dynamics\.com\/?$/i.test(url.trim())
      ? 'Unusual host - Dataverse URLs normally end in .dynamics.com.'
      : undefined
  const tenantHint =
    tenantId && !GUID.test(tenantId.trim())
      ? 'Not a GUID. A verified domain (contoso.onmicrosoft.com) works too; the Tenant check will tell.'
      : undefined
  const secretHint = GUID.test(secret.trim())
    ? 'This looks like a Secret ID (a GUID). You need the secret Value - the client sees it only once, when they create the secret.'
    : undefined

  const pickSameAs = (value: string) => {
    setSameAs(value)
    const src = others.find((o) => o.id === value)
    if (src) {
      setTenantId(src.tenantId)
      setClientId(src.clientId)
      setSecret('')
    }
  }

  const submit = () => {
    if (Object.keys(problems).length > 0) return
    onSave(id, {
      name: name.trim(),
      url: url.trim().replace(/\/$/, ''),
      tenantId: tenantId.trim(),
      clientId: clientId.trim(),
      clientSecret: sameAs ? undefined : secret || undefined,
      secretFrom: sameAs || undefined,
      role,
      requireApproval,
    })
  }

  // Only nag about a field once something is in it; the Save button stays disabled either way.
  const show = (key: string, value: string) => (value ? problems[key] : undefined)

  return (
    <div className="setup-form">
      <Field label="Name" required validationMessage={show('name', name)} hint={!existing && id ? `Id: ${id}` : undefined}>
        <Input value={name} onChange={(_, d) => setName(d.value)} placeholder="Contoso Dev" />
      </Field>
      <Field
        label="Environment URL"
        required
        validationMessage={show('url', url) ?? urlHint}
        validationState={show('url', url) ? 'error' : urlHint ? 'warning' : 'none'}
      >
        <Input value={url} onChange={(_, d) => setUrl(d.value)} placeholder="https://contoso-dev.crm4.dynamics.com" />
      </Field>

      {reusable.length > 0 && (
        <Field label="Same app registration as" hint="When the client uses one app registration for several environments.">
          <Dropdown
            value={sameAsEnv?.name ?? 'No - enter its details below'}
            selectedOptions={[sameAs]}
            onOptionSelect={(_, d) => pickSameAs(d.optionValue ?? '')}
          >
            <Option value="">No - enter its details below</Option>
            {reusable.map((o) => (
              <Option key={o.id} value={o.id}>
                {o.name}
              </Option>
            ))}
          </Dropdown>
        </Field>
      )}

      <Field
        label="Directory (tenant) ID"
        required
        validationMessage={show('tenantId', tenantId) ?? tenantHint}
        validationState={show('tenantId', tenantId) ? 'error' : tenantHint ? 'warning' : 'none'}
      >
        <Input value={tenantId} disabled={!!sameAs} onChange={(_, d) => setTenantId(d.value)} placeholder="00000000-0000-0000-0000-000000000000" />
      </Field>
      <Field label="Application (client) ID" required validationMessage={show('clientId', clientId)}>
        <Input value={clientId} disabled={!!sameAs} onChange={(_, d) => setClientId(d.value)} placeholder="00000000-0000-0000-0000-000000000000" />
      </Field>
      {sameAs ? (
        <Field label="Client secret" hint={`Uses the saved secret of ${sameAsEnv?.name}.`}>
          <Input type="password" disabled value="" placeholder="Shared" />
        </Field>
      ) : (
        <Field
          label="Client secret value"
          required={!existing?.hasSecret}
          validationMessage={secretHint}
          validationState={secretHint ? 'warning' : 'none'}
          hint={existing?.hasSecret ? 'A secret is saved. Leave empty to keep it.' : 'Stored encrypted for your Windows user only. Never shown again.'}
        >
          <Input
            type="password"
            value={secret}
            onChange={(_, d) => setSecret(d.value)}
            placeholder={existing?.hasSecret ? '•••••••• saved' : ''}
            autoComplete="new-password"
          />
        </Field>
      )}

      <div className="setup-form-row">
        <Field label="Use as">
          <Dropdown value={roleLabels[role]} selectedOptions={[role]} onOptionSelect={(_, d) => d.optionValue && setRole(d.optionValue as EnvRole)}>
            {(Object.keys(roleLabels) as EnvRole[]).map((r) => (
              <Option key={r} value={r}>
                {roleLabels[r]}
              </Option>
            ))}
          </Dropdown>
        </Field>
        <Field label="Approval" hint="Apply needs an explicit tick, e.g. for Prod.">
          <Switch checked={requireApproval} onChange={(_, d) => setRequireApproval(d.checked)} label={requireApproval ? 'Required' : 'Not required'} />
        </Field>
      </div>

      <div className="actions">
        <Button
          appearance="primary"
          icon={busy ? <Spinner size="tiny" /> : <ArrowRightRegular />}
          iconPosition="after"
          disabled={busy || Object.keys(problems).length > 0}
          onClick={submit}
        >
          Save and run checks
        </Button>
        {onDelete && (
          <Button appearance="subtle" icon={<DeleteRegular />} disabled={busy} onClick={onDelete}>
            Remove environment
          </Button>
        )}
      </div>
    </div>
  )
}
