# Architecture

How the Contact Center ALM accelerator is put together: a code app for the UI, a backend for the cross-environment work, one manifest that drives both.

## Two parts

```
Power Apps code app (React/TS, in Dynamics)        Backend (service principal)
┌──────────────────────────────────────┐          ┌──────────────────────────────┐
│ Pick source and target                │          │ Read  -> natural-key index   │   Dev
│ See the diff, pick what moves         │  HTTPS   │ Diff  -> resolve GUIDs to key│   Test
│ Build a plan, dry-run, apply          │ ───────▶ │ Plan  -> ordered operations  │──▶ Acc
│ Watch stage progress, roll back       │  via     │ Write -> upsert by resolved key   │   Prod
│                                        │ connector│ Rollback -> snapshot restore │
└──────────────────────────────────────┘          └──────────────────────────────┘
        Fluent UI v9                                one app registration,
        @microsoft/power-apps SDK                   app user in all four environments
```

The code app is the front end. It runs inside the Power Apps host, which handles Entra sign-in and routes outbound calls through a connector so DLP applies. The app never talks to the four Dataverse environments itself.

The backend does the heavy lifting: read, compare, plan, write, rollback, under a service principal that is an Application User in every environment. It is one engine, `backend/function-app/Modules/CcAlm`, shared by the Azure Function and the CLI (`backend/cli`) — same manifest, same GUID remapping, same stage order, same ruleset double-write, so there is nothing to keep in sync between "the real thing" and "the reference".

## Why a backend at all

The code app's connectors are scoped to the environment it runs in. One app cannot cleanly read and write four environments through the Dataverse connector. A service principal calling each environment's Web API gives full control over GUID remapping, upsert, ordering, and the ruleset double-write, and keeps Prod writes off the browser.

There is a lighter variant. See the two options below.

## The app, in layers

| Layer | Files | Job |
| --- | --- | --- |
| Shell | `App.tsx`, `PowerProvider.tsx` | Theme, header, and the host handshake (`setConfig` + `getContext`). |
| Page | `pages/ComparePage.tsx` | Drives the flow: compare, select, plan, run, roll back. |
| Components | `components/*` | Environment bar, summary cards, diff table, detect-only panel, plan panel, run progress, apply dialog. |
| Flow | `hooks/useAlmFlow.ts` | State machine over the service. Holds diff, plan, run, and errors. |
| Service | `services/*` | The seam. One interface, two adapters. |
| Types | `types/alm.ts` | The API contract, shared by UI and backend. |

## The service seam

Every component depends on one interface, `AlmService`:

```ts
listEnvironments(): Promise<EnvironmentRef[]>
compare(sourceId, targetId, tables?): Promise<DiffModel>
plan(diff, selection?): Promise<Plan>
apply(plan, mode, approved): Promise<Run>
getRun(runId): Promise<Run>
rollback(runId): Promise<Run>
```

Two adapters implement it:

- **mock** (`mockAlmService.ts`): in-memory sample data, real workstreams and queues and rulesets. The app runs and demos with no backend. Set `VITE_ALM_SOURCE=mock`.
- **backend** (`backendAlmService.ts`): direct HTTP to the deployed Function, for local dev. Set `VITE_ALM_SOURCE=backend` and `VITE_ALM_BACKEND_URL`.
- **connector** (`connectorAlmService.ts`): calls the backend through the generated custom-connector client. The path the published app uses. Set `VITE_ALM_SOURCE=connector`.

Swapping one for the other never touches a component. `generatedConnector.ts` is the single seam to the generated connector client, wired after `pac code add-data-source`.

## Two options for the backend

The app is the same for both. Only the adapter differs.

| | A: Backend service (recommended) | B: In-app connections |
| --- | --- | --- |
| Cross-environment work | Azure Function under a service principal | Signed-in admin's connections to each environment |
| Reaches other environments | Custom connector to the Function | Multiple Dataverse connections, one per environment |
| Prod writes | Server-side, service principal, approval gate | Browser-side, under the user's rights |
| Extra infrastructure | Azure hosting | None |
| Fit | Unattended, pipeline-friendly, safer for Prod | Self-contained, simpler, weaker for Prod |

Option A is the default here, because this tool writes to Prod. The backend runs the reference engine's logic. The published app reaches it through the custom connector via `connectorAlmService`.

## The API contract

The backend exposes REST over HTTPS, Entra-protected. The shapes match `types/alm.ts`.

| Endpoint | Purpose |
| --- | --- |
| `GET /environments` | List registered environments. |
| `POST /compare` | Diff source against target. Returns the diff model plus detect-only findings. |
| `POST /plan` | Ordered write operations from an approved selection. |
| `POST /apply` | Run the plan (`mode: dryRun \| apply`). Stateless: takes source, target, and selection, returns the run record. |
| `GET /run/{id}` | Run state, stage progress, warnings. Poll this. |
| `POST /run/{id}/rollback` | Restore from the run snapshot. |

The backend implements this in `backend/function-app` as PowerShell HTTP triggers over the engine. Apply runs synchronously today and returns the run; the polling shape stays in the contract so a later move to Durable Functions needs no app change. See `backend.md`.

User auth to the backend (the signed-in app user) stays separate from the service principal the backend uses for Dataverse. Keep them separate.

## The manifest drives everything

`config/manifest.json` holds the table order, match keys, lookups, move modes, and detect-only rules. The backend reads it to know what to move and how. The reference engine reads the same file. Keep it as data so the engine and the docs stay in sync. See `manifest.md`.

## What the tool never moves

Per-environment provisioning. The backend detects these and reports them. The app shows them in the detect-only panel. Nobody hand-moves them and nothing uses CMT.

- ACS phone numbers and number acquisition
- Event Grid subscriptions
- Copilot Studio voice and IVR agents (move by solution, then rewire connection references)
- Teams and third-party channel accounts (re-auth per environment)
- Customer Voice surveys (sync per environment)

## Known limits

- Writing routing config through the Web API is not a Microsoft-supported path. Version-detect the ruleset JSON and fail loud. Expect breakage on product updates.
- Async provisioning has no done signal. The engine polls with a timeout and warns.
- Rollback cannot reverse provisioning side-effects. Snapshot restores records; a half-provisioned workstream needs a manual look. It does not delete records the run created.
- Operating-hours calendar association is a second pass, not yet wired to a live org.
- A record whose dependency has not landed in target yet - a ruleset referencing a queue not in the plan, a step whose parent config is not in target - is skipped with a warning rather than written half-broken. The run then reports `PartiallyFailed`; that is a "some records need their dependency migrated first" signal, not necessarily a bug. Selecting a record in the app auto-selects what it depends on, which is usually enough to avoid the skip in the first place.
