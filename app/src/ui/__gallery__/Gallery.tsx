// Component gallery for the Capgemini UI layer. NOT imported by the app.
// To view it, temporarily render <Gallery /> from a scratch entry, e.g. in a local main.tsx:
//   import '../styles'; createRoot(el).render(<Gallery />)
// It renders every component twice: once under data-theme="light", once under data-theme="dark".
import { useState, type ReactNode } from 'react'
import { AddRegular, ArrowSyncRegular, DeleteRegular, EditRegular } from '@fluentui/react-icons'
import {
  Accordion,
  AppFooter,
  AppHeader,
  Badge,
  Button,
  Card,
  Checkbox,
  Dialog,
  Disclosure,
  DisclosureChevron,
  EmptyState,
  FilterChips,
  IconButton,
  Input,
  KeyValue,
  Link,
  Notice,
  Panel,
  ProgressBar,
  SearchInput,
  Select,
  Skeleton,
  SkeletonText,
  Spinner,
  STATUS_KINDS,
  STATUS_STYLES,
  StatusDot,
  StatusLabel,
  Stepper,
  Switch,
  Table,
  TBody,
  Td,
  Th,
  THead,
  Tabs,
  Tag,
  Textarea,
  ThemeToggle,
  Toaster,
  Tooltip,
  Tr,
  useToast,
  type StepItem,
} from '..'

const steps: StepItem[] = [
  { id: 'connect', label: 'Connect environments', state: 'done' },
  { id: 'compare', label: 'Compare', description: '214 records', state: 'current' },
  { id: 'plan', label: 'Review plan', state: 'upcoming' },
  { id: 'apply', label: 'Apply', state: 'upcoming' },
]

const stepsWithIssues: StepItem[] = [
  { id: 'a', label: 'Connect', state: 'done' },
  { id: 'b', label: 'Validate', state: 'warning', description: '2 warnings' },
  { id: 'c', label: 'Apply', state: 'error', description: '1 failed' },
  { id: 'd', label: 'Verify', state: 'current' },
]

function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section style={{ display: 'grid', gap: 'var(--space-4)', marginBottom: 'var(--space-12)' }}>
      <h2 className="t-h3">{title}</h2>
      {children}
    </section>
  )
}

const row = { display: 'flex', flexWrap: 'wrap', gap: 'var(--space-3)', alignItems: 'center' } as const

function ToastDemo() {
  const { toast } = useToast()
  return (
    <div style={row}>
      <Button size="sm" variant="secondary" onClick={() => toast({ tone: 'success', title: 'Plan applied', message: '12 records updated.' })}>
        Show success toast
      </Button>
      <Button size="sm" variant="secondary" onClick={() => toast({ tone: 'error', title: 'Apply failed', message: 'The target environment refused the connection.' })}>
        Show error toast
      </Button>
    </div>
  )
}

function Showcase({ theme }: { theme: 'light' | 'dark' }) {
  const [tab, setTab] = useState('compare')
  const [headerTab, setHeaderTab] = useState('compare')
  const [chips, setChips] = useState<string[]>(['changed'])
  const [query, setQuery] = useState('queue')
  const [sw, setSw] = useState(true)
  const [dialog, setDialog] = useState(false)
  const [selected, setSelected] = useState<string[]>(['q2'])
  const [currentStep, setCurrentStep] = useState('compare')

  const rows = [
    { id: 'q1', name: 'Billing queue', kind: 'new' as const, owner: 'Contoso support', count: 3 },
    { id: 'q2', name: 'Escalations', kind: 'changed' as const, owner: 'Tier 2', count: 12 },
    { id: 'q3', name: 'Legacy voice', kind: 'extra' as const, owner: 'Retired', count: 0 },
    { id: 'q4', name: 'General enquiries', kind: 'same' as const, owner: 'Tier 1', count: 41 },
  ]
  const allSelected = selected.length === rows.length
  const someSelected = selected.length > 0 && !allSelected

  return (
    <div data-theme={theme} style={{ background: 'var(--page-background)', color: 'var(--text-primary)' }}>
      <AppHeader
        productName="Contact Center ALM"
        subtitle={`Gallery, ${theme} theme`}
        actions={
          <>
            <ThemeToggle tone="heavy" />
            <Button tone="heavy" size="sm" variant="secondary">
              Sign out
            </Button>
          </>
        }
        nav={
          <Tabs
            tone="heavy"
            aria-label="Sections"
            selected={headerTab}
            onSelect={setHeaderTab}
            items={[
              { id: 'setup', label: 'Setup' },
              { id: 'compare', label: 'Compare', badge: 12 },
              { id: 'history', label: 'History' },
            ]}
          />
        }
      />

      <main style={{ padding: 'var(--space-8) var(--space-6)', maxWidth: 1200, margin: '0 auto' }}>
        <h1 className="t-h1" style={{ marginBottom: 'var(--space-8)' }}>
          Get the future you want
        </h1>

        <Section title="Type">
          {['h1', 'h2', 'h3', 'h4', 'h5', 'body', 'body-strong', 'body-small', 'caption', 'label', 'nav', 'code'].map((t) => (
            <p key={t} className={`t-${t}`}>
              {t}: Move configuration between environments
            </p>
          ))}
        </Section>

        <Section title="Buttons">
          <div style={row}>
            <Button>Compare environments</Button>
            <Button variant="secondary">Cancel</Button>
            <Button icon href="#">Read the guide</Button>
            <Button size="sm" leadingIcon={<AddRegular />}>
              Add environment
            </Button>
            <Button busy>Applying</Button>
            <Button disabled>Disabled</Button>
          </div>
          <div style={row}>
            <IconButton label="Refresh" icon={<ArrowSyncRegular fontSize={20} />} />
            <IconButton label="Edit" size="sm" variant="secondary" icon={<EditRegular fontSize={20} />} />
            <IconButton label="Delete" quiet icon={<DeleteRegular fontSize={20} />} />
            <IconButton label="Pinned" pressed icon={<AddRegular fontSize={20} />} />
            <Tooltip content="Compares every queue, workstream and routing rule.">
              <Button size="sm" variant="secondary">
                Hover or focus me
              </Button>
            </Tooltip>
          </div>
          <div className="ui-on-heavy" style={{ ...row, background: 'var(--surface-azur-heavy)', padding: 'var(--space-6)' }}>
            <Button tone="heavy">Start now</Button>
            <Button tone="heavy" variant="secondary" icon>
              Learn more
            </Button>
            <IconButton tone="heavy" label="Refresh" icon={<ArrowSyncRegular fontSize={20} />} />
            <Link variant="inverse" underline href="#">
              Inverse link
            </Link>
          </div>
        </Section>

        <Section title="Links and tags">
          <p className="t-body">
            Read the <Link underline href="#">release notes</Link> before you apply, or open the{' '}
            <Link variant="highlight" href="#">
              highlighted guide
            </Link>
            .
          </p>
          <div>
            <Tag>Queues</Tag>
            <Tag onRemove={() => undefined} removeLabel="Remove Workstreams filter">
              Workstreams
            </Tag>
            <Tag quiet>Read only</Tag>
          </div>
          <FilterChips
            aria-label="Filter by status"
            selected={chips}
            onChange={setChips}
            items={[
              { id: 'new', label: 'New', count: 3 },
              { id: 'changed', label: 'Changed', count: 12 },
              { id: 'extra', label: 'Only in target', count: 1 },
              { id: 'same', label: 'Same', count: 41 },
            ]}
          />
        </Section>

        <Section title="Status">
          <div style={row}>
            {STATUS_KINDS.map((k) => (
              <StatusLabel key={k} kind={k} title={STATUS_STYLES[k].description} />
            ))}
          </div>
          <div style={row}>
            <StatusDot kind="failed" label="Failed" />
            <Badge>12</Badge>
            <Badge tone="strong">3</Badge>
            <Spinner size="sm" />
            <Spinner />
          </div>
          <div style={{ display: 'grid', gap: 'var(--space-4)', maxWidth: 480 }}>
            <ProgressBar label="Applying changes" value={45} showValue />
            <ProgressBar label="Reading target environment" />
          </div>
        </Section>

        <Section title="Tabs and stepper">
          <Tabs
            aria-label="Record types"
            selected={tab}
            onSelect={setTab}
            items={[
              { id: 'compare', label: 'Queues', badge: 4 },
              { id: 'ws', label: 'Workstreams', badge: 12 },
              { id: 'rules', label: 'Routing rules' },
              { id: 'off', label: 'Disabled', disabled: true },
            ]}
          />
          <Stepper
            steps={steps.map((s) => ({ ...s, state: s.id === currentStep ? 'current' : s.state === 'current' ? 'done' : s.state }))}
            onSelect={setCurrentStep}
          />
          <Stepper steps={stepsWithIssues} />
          <div style={{ maxWidth: 360, border: '1px dashed var(--border-primary)', padding: 'var(--space-3)' }}>
            <Stepper steps={steps} />
          </div>
        </Section>

        <Section title="Notices">
          <Notice tone="info" title="Comparison is read only" live="none">
            Nothing changes until you apply the plan.
          </Notice>
          <Notice tone="success" live="none" onDismiss={() => undefined}>
            Connected to both environments.
          </Notice>
          <Notice
            tone="warning"
            title="2 records need a manual step"
            live="none"
            actions={
              <Button size="sm" variant="secondary">
                Show records
              </Button>
            }
          >
            Skills cannot be moved by the API. Recreate them in the target.
          </Notice>
          <Notice tone="error" title="Apply failed" live="none" onDismiss={() => undefined}>
            The target refused the request. Check the connection and try again.
          </Notice>
          <ToastDemo />
        </Section>

        <Section title="Forms">
          <div style={{ display: 'grid', gap: 'var(--space-6)', gridTemplateColumns: 'repeat(auto-fit, minmax(min(100%, 280px), 1fr))' }}>
            <Input label="Environment URL" placeholder="https://contoso.crm.dynamics.com" hint="The Dataverse URL of the source." />
            <Input label="Client ID" defaultValue="not-a-guid" error="Enter a GUID, for example 00000000-0000-0000-0000-000000000000." />
            <Select
              label="Target environment"
              placeholder="Select an environment"
              options={['Development', 'Test', 'Acceptance', { value: 'prod', label: 'Production' }]}
            />
            <Input label="Read only" readOnly defaultValue="contoso-dev" />
            <Input label="Disabled" disabled defaultValue="Not available" />
            <SearchInput label="Search records" hideLabel placeholder="Search records" value={query} onChange={setQuery} />
            <Textarea label="Notes" hint="Shown in the run history." />
            <div style={{ display: 'grid', gap: 'var(--space-3)' }}>
              <Checkbox label="Include inactive records" defaultChecked />
              <Checkbox label="Mixed parent" indeterminate />
              <Checkbox label="Disabled" disabled />
              <Checkbox label="With a hint" hint="Applies to queues only." />
              <Switch label="Dry run" checked={sw} onChange={setSw} />
              <Switch label="Disabled switch" checked={false} onChange={() => undefined} disabled />
            </div>
          </div>
        </Section>

        <Section title="Table">
          <Table caption="Queues compared between Development and Test" sticky maxHeight={320}>
            <THead>
              <Tr noHover>
                <Th>Name</Th>
                <Th>
                  <Checkbox
                    label="Select all"
                    hideLabel
                    checked={allSelected}
                    indeterminate={someSelected}
                    onChange={() => setSelected(allSelected ? [] : rows.map((r) => r.id))}
                  />
                </Th>
                <Th>Status</Th>
                <Th>Owner</Th>
                <Th numeric>Items</Th>
              </Tr>
            </THead>
            <TBody>
              {rows.map((r) => {
                const on = selected.includes(r.id)
                return (
                  <Tr key={r.id} selected={on}>
                    <Td>{r.name}</Td>
                    <Td shrink>
                      <Checkbox
                        label={`Select ${r.name}`}
                        hideLabel
                        checked={on}
                        onChange={() => setSelected(on ? selected.filter((x) => x !== r.id) : [...selected, r.id])}
                      />
                    </Td>
                    <Td>
                      <StatusLabel kind={r.kind} />
                    </Td>
                    <Td>{r.owner}</Td>
                    <Td numeric>{r.count}</Td>
                  </Tr>
                )
              })}
            </TBody>
          </Table>
        </Section>

        <Section title="Containers">
          <Panel
            title="Plan"
            description="What will change in Test when you apply."
            actions={
              <>
                <Button size="sm" variant="secondary">
                  Export
                </Button>
                <Button size="sm" onClick={() => setDialog(true)}>
                  Apply plan
                </Button>
              </>
            }
          >
            <KeyValue
              items={[
                { label: 'Source', value: 'contoso-dev.crm4.dynamics.com' },
                { label: 'Target', value: 'contoso-test.crm4.dynamics.com' },
                { label: 'Changes', value: '3 new, 12 changed' },
              ]}
            />
            <Disclosure
              trigger={({ open, triggerProps }) => (
                <button {...triggerProps} className="ui-disclosure-trigger">
                  <DisclosureChevron open={open} /> Show field differences
                </button>
              )}
            >
              <p className="t-body-small">Description, routing method and capacity differ.</p>
            </Disclosure>
          </Panel>
          <div style={{ display: 'grid', gap: 'var(--space-6)', gridTemplateColumns: 'repeat(auto-fit, minmax(min(100%, 260px), 1fr))' }}>
            <Card eyebrow="Guide" eyebrowHref="#" title="Move a workstream" href="#" meta={['5 min read', 'Updated today']} footer={<Link href="#">Open the guide</Link>}>
              Workstreams carry their routing rules with them.
            </Card>
            <Card bordered title="Bordered card" meta="No shadow" footer={<Button size="sm" variant="secondary">Open</Button>}>
              Separated by border-primary and spacing, not elevation.
            </Card>
          </div>
          <Accordion
            defaultOpen={0}
            items={[
              { title: 'What does compare read?', content: 'Queues, workstreams, routing rules and their links.' },
              { title: 'Does compare change anything?', content: 'No. Only apply writes to the target.' },
            ]}
          />
          <Panel title="Loading" titleAs="h3" aria-busy="true">
            <Skeleton variant="block" height={48} />
            <SkeletonText lines={3} />
            <Skeleton variant="circle" />
          </Panel>
          <Panel>
            <EmptyState title="No differences found" action={<Button size="sm">Compare again</Button>}>
              The two environments match for the selected record types.
            </EmptyState>
          </Panel>
        </Section>
      </main>

      <AppFooter left={<span>Capgemini · Contact Center ALM v0.2.0</span>} right={<Link href="#">Release notes</Link>} />

      <Dialog
        open={dialog}
        onClose={() => setDialog(false)}
        title="Apply the plan to Test?"
        description="15 records will be written to contoso-test."
        actions={
          <>
            <Button variant="secondary" onClick={() => setDialog(false)}>
              Cancel
            </Button>
            <Button onClick={() => setDialog(false)}>Apply plan</Button>
          </>
        }
      >
        <KeyValue compact items={[{ label: 'New', value: '3' }, { label: 'Changed', value: '12' }]} />
      </Dialog>
    </div>
  )
}

/** Renders the whole kit in the light theme, then in the dark theme. */
export function Gallery() {
  return (
    <Toaster>
      <Showcase theme="light" />
      <Showcase theme="dark" />
    </Toaster>
  )
}

export default Gallery
