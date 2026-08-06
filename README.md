# Contact Center ALM for Dynamics 365

**A Power Apps code app that compares and moves Contact Center config across environments, no Configuration Migration tool, no manual GUID edits.**

Contact Center ALM is the part everyone dreads. Workstreams, queues, routing rules, overflow rules and opening hours are content, not structure, so a solution does not carry them. The Configuration Migration tool does, but it means a schema file, a hand edit of `data.xml`, a double import for rulesets, and a calendar fix you have to remember. Every promotion. By hand.

So this puts it behind a UI.

> **New here? Follow [docs/getting-started.md](docs/getting-started.md).** It goes from nothing to a working tool, step by step, no prior Power Platform or Azure knowledge needed.

You open the app in Dynamics, pick a source and a target, and see what differs. The tool matches records on their names instead of their GUIDs, so two identical workstreams do not read as "everything changed". You pick what to move, dry-run it, then apply. It writes in the right order, remaps the GUIDs, and waits for workstream provisioning before it moves on. Any environment to any environment.

## What you get

| Part | What it is |
| --- | --- |
| Code app (`app/`) | React + TypeScript, Fluent UI, the `@microsoft/power-apps` SDK. The UI: environment picker, diff, plan, dry-run, apply, rollback. |
| Backend (`backend/function-app/`) | A PowerShell Azure Function that wraps the engine, exposing compare/plan/apply/rollback over HTTP under a service principal. |
| Reference engine (`backend/reference-engine-powershell/`) | The exact logic the backend runs, in PowerShell, so it runs standalone and documents every Web API operation. |
| Build and deploy (`build.ps1`, `scripts/`) | Build the app, `pac code init`, `pac code push`. |
| Manifest (`config/manifest.json`) | Table order, match keys, lookups, move modes, detect-only rules. The app and the engine read from it. |

## How it fits together

```
Power Apps code app (in Dynamics)  ──connector──▶  Backend (service principal)  ──▶  Dev / Test / Acc / Prod
     UI: compare, plan, apply, roll back              read, diff, plan, write, rollback      Web API
```

The code app is the front end. The Power Apps host signs the user in and routes calls through a connector so DLP applies. The backend does the cross-environment work under a service principal that is an Application User in every environment. Full reasoning in [docs/architecture.md](docs/architecture.md).

## Runs on day one, no backend

The app ships with a mock data source: real workstreams, queues, and routing rulesets in memory. Every screen works before any backend exists.

```bash
cd app
npm install
npm run dev
```

Swap to the real backend with one env var (`VITE_ALM_SOURCE=backend`). No component changes. The UI depends on one service interface with two adapters, mock and backend, so the front end is done and stable while the backend gets built.

## Two options for the backend

The app is identical for both. Only the data adapter differs.

- **A, backend service (default).** An Azure Function under a service principal, reached through a custom connector. Robust, pipeline-friendly, keeps Prod writes off the browser. Needs Azure hosting.
- **B, in-app connections.** The signed-in admin's own connections to each environment, no Azure. Self-contained, but cross-environment orchestration runs in the browser under the user's rights, which is weaker for unattended Prod writes.

This repo targets A. See the table in [docs/architecture.md](docs/architecture.md).

## What it does not move

Per-environment provisioning. The tool detects these, shows them in the app, and leaves them alone. No hand-moving, no CMT.

- ACS phone numbers and number acquisition
- Event Grid subscriptions
- Copilot Studio voice and IVR agents (move by solution, then rewire connection references)
- Teams and third-party channel accounts (re-auth per environment)
- Customer Voice surveys (sync per environment)

## Prerequisites

- Node.js LTS and npm
- Power Platform CLI (`pac`)
- Code Apps enabled on the environment (admin center -> environment -> Settings -> Product -> Features)
- Power Apps Premium license for anyone running the published app
- For option A: an Entra app registration as an Application User in each environment ([docs/backend-service-principal.md](docs/backend-service-principal.md))

## Get started

The full step-by-step is in [docs/getting-started.md](docs/getting-started.md). The short version:


```bash
git clone https://github.com/peterruiter/d365-contactcenter-alm.git
cd d365-contactcenter-alm/app
npm install
npm run dev        # mock data, no environment needed
```

Deploy to an environment:

```powershell
./scripts/init-app.ps1 -EnvironmentUrl https://contoso-dev.crm4.dynamics.com   # once per clone
./scripts/deploy.ps1  -EnvironmentUrl https://contoso-dev.crm4.dynamics.com
```

Full walk-through in [docs/setup.md](docs/setup.md) and [docs/usage.md](docs/usage.md).

Stand up the backend (Azure Function + connector):

```powershell
./scripts/deploy-backend.ps1 -ResourceGroup rg-ccalm -FunctionApp ccalm-func-nl -Location westeurope -EnvironmentsFile ./environments.json
```

Steps and auth in [docs/backend.md](docs/backend.md).

## Two things that catch everyone out

1. **Enable Code Apps on the environment first.** Without the feature toggle, `pac code` commands fail silently and you lose an hour wondering why nothing deploys.
2. **Writing routing config through the API is not a Microsoft-supported path.** Their process is CMT plus a manual `data.xml` edit. This automates the same writes and will break the day the ruleset JSON shape changes. The engine version-detects and fails loud rather than mis-writing. Test after every product update.

## Known limits

- Async provisioning has no done signal. The engine polls with a timeout and warns, it does not pretend success.
- Rollback restores records but cannot reverse provisioning side-effects. A half-provisioned workstream needs a manual look.
- Operating-hours calendar association is a second pass, not yet wired to a live org.
- Some entity set names (quick replies, tags) need confirming per org. The manifest notes them.

## Repository layout

| Path | Contents |
| --- | --- |
| `app/` | The code app. `src/components`, `src/pages`, `src/services` (the mock and backend adapters), `src/hooks`, `src/types`. |
| `config/manifest.json` | Table order, match keys, lookups, move modes, detect-only rules. |
| `backend/function-app/` | The backend: PowerShell Azure Function wrapping the engine (`Modules/CcAlm`). |
| `backend/cli/` | The same engine as a command-line tool, for pipelines. |
| `connector/` | Custom connector definition (OpenAPI + Entra auth). |
| `scripts/` | `deploy.ps1`, `init-app.ps1`. |
| `build.ps1` | Install, typecheck, build the app. |
| `docs/` | [getting-started](docs/getting-started.md), [architecture](docs/architecture.md), [setup](docs/setup.md), [usage](docs/usage.md), [backend](docs/backend.md), [manifest](docs/manifest.md), [backend service principal](docs/backend-service-principal.md) |

## Roadmap

- [x] Backend service (PowerShell Azure Function) wrapping the engine
- [x] Custom connector definition for the backend
- [x] Connector adapter wired into the app (published app calls the backend through the connector)
- [ ] Live run polling and streamed stage progress
- [ ] Manual-match override for records the engine cannot pair on name
- [ ] Operating-hours calendar-row copy wired to a live org

## Credits and licence

Table set and sequence follow Microsoft's [Contact Center configuration migration docs](https://learn.microsoft.com/en-us/dynamics365/customer-service/administer/migrate-channel-config-using-solutions). Sits next to [d365-conversation-diagnostics](https://github.com/peterruiter/d365-conversation-diagnostics), same idea: take the painful part out of CMT and Azure and put it somewhere a consultant can run it.

MIT.
