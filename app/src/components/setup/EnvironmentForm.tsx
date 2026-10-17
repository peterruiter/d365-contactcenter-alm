import { useMemo, useState } from 'react'
import { DeleteRegular } from '@fluentui/react-icons'
import { Button, Input, Select, Switch } from '../../ui'
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

const ROLE_OPTIONS: Array<{ value: EnvRole; label: string }> = [
  { value: 'any', label: 'Source or target' },
  { value: 'source', label: 'Source only' },
  { value: 'target', label: 'Target only' },
]

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
    if (!name.trim()) p.name = 'Give it a name, for example "Contoso Dev".'
    else if (!existing && !id) p.name = 'Use at least one letter or digit.'
    else if (!existing && takenIds.includes(id)) p.name = `There is already an environment called "${id}".`
    if (!u) p.url = 'Required.'
    else if (!/^https:\/\/[a-z0-9.-]+$/i.test(u)) p.url = 'Only the address, for example https://contoso-dev.crm4.dynamics.com, without a path.'
    if (!tenantId.trim()) p.tenantId = 'Required.'
    if (!GUID.test(clientId.trim())) p.clientId = 'A GUID: the Application (client) ID on the app registration overview.'
    if (!sameAs && !secret && !existing?.hasSecret) p.secret = 'Required.'
    return p
  }, [name, url, tenantId, clientId, secret, sameAs, existing, id, takenIds])

  const show = (key: string, value: string) => (value ? problems[key] : undefined)
  const urlHint = url && !problems.url && !/\.dynamics\.com\/?$/i.test(url.trim()) ? 'Unusual address: Dataverse addresses normally end in .dynamics.com.' : undefined
  const secretHint = GUID.test(secret.trim())
    ? 'This looks like a Secret ID (a GUID). You need the secret Value, which the client sees only once, when they create the secret.'
    : existing?.hasSecret
      ? 'A secret is saved. Leave this empty to keep it.'
      : 'Stored encrypted for your Windows user only, and never shown again.'

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

  return (
    <form
      className="setup-form"
      onSubmit={(e) => {
        e.preventDefault()
        submit()
      }}
    >
      <Input label="Name" value={name} onChange={(e) => setName(e.target.value)} placeholder="Contoso Dev" error={show('name', name)} hint={!existing && id ? `Saved as ${id}` : undefined} />
      <Input label="Environment address" value={url} onChange={(e) => setUrl(e.target.value)} placeholder="https://contoso-dev.crm4.dynamics.com" error={show('url', url)} hint={urlHint} />
      {reusable.length > 0 && (
        <Select
          label="Same app registration as"
          hint="When the client uses one app registration for several environments."
          value={sameAs}
          onChange={(e) => pickSameAs(e.target.value)}
          options={[{ value: '', label: 'No, enter its details below' }, ...reusable.map((o) => ({ value: o.id, label: o.name }))]}
        />
      )}
      <Input label="Directory (tenant) ID" value={tenantId} disabled={!!sameAs} onChange={(e) => setTenantId(e.target.value)} placeholder="00000000-0000-0000-0000-000000000000" error={show('tenantId', tenantId)} />
      <Input label="Application (client) ID" value={clientId} disabled={!!sameAs} onChange={(e) => setClientId(e.target.value)} placeholder="00000000-0000-0000-0000-000000000000" error={show('clientId', clientId)} />
      {sameAs ? (
        <Input label="Client secret" value="" disabled placeholder="Shared" hint={`Uses the saved secret of ${sameAsEnv?.name}.`} />
      ) : (
        <Input
          label="Client secret value"
          type="password"
          autoComplete="new-password"
          value={secret}
          onChange={(e) => setSecret(e.target.value)}
          placeholder={existing?.hasSecret ? '•••••••• saved' : ''}
          hint={secretHint}
        />
      )}
      <div className="setup-form__row">
        <Select label="Use as" value={role} onChange={(e) => setRole(e.target.value as EnvRole)} options={ROLE_OPTIONS} />
        <div>
          <Switch checked={requireApproval} onChange={setRequireApproval} label="Require approval to apply" />
          <p className="muted t-body-small" style={{ marginTop: 'var(--space-2)' }}>For production: applying needs an explicit tick.</p>
        </div>
      </div>
      <div className="row">
        <Button type="submit" busy={busy} disabled={busy || Object.keys(problems).length > 0}>
          Save and check
        </Button>
        {onDelete && (
          <Button variant="secondary" leadingIcon={<DeleteRegular />} disabled={busy} onClick={onDelete}>
            Remove environment
          </Button>
        )}
      </div>
    </form>
  )
}
