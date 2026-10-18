# Contact Center ALM for Dynamics 365

[![Release](https://img.shields.io/github/v/release/peterruiter/d365-contactcenter-alm)](https://github.com/peterruiter/d365-contactcenter-alm/releases/latest)

**A Power Apps code app that compares and moves Contact Center config across environments, no Configuration Migration tool, no manual GUID edits.**

Contact Center ALM is the part everyone dreads. Workstreams, queues, routing rules, overflow rules and opening hours are content, not structure, so a solution does not carry them. The Configuration Migration tool does, but it means a schema file, a hand edit of `data.xml`, a double import for rulesets, and a calendar fix you have to remember. Every promotion. By hand.

So this puts it behind a UI.

> **New here? Follow [docs/getting-started.md](docs/getting-started.md).** It goes from nothing to a working tool, step by step, no prior Power Platform or Azure knowledge needed.

You open the app in Dynamics, pick a source and a target, and see what differs. The tool matches records on their names instead of their GUIDs, so two identical workstreams do not read as "everything changed". You pick what to move, dry-run it, then apply. It writes in the right order, remaps the GUIDs, and waits for workstream provisioning before it moves on. Any environment to any environment.

## What you get

| Part | What it is |
| --- | --- |
| Code app (`app/`) | React + TypeScript on the Capgemini (Zodiak) design system, the `@microsoft/power-apps` SDK. A guided flow: environments, review what differs, plan check with dependency preflight, dry run, apply, rollback, run history. |
| Backend (`backend/function-app/`) | A PowerShell Azure Function that wraps the engine, exposing compare/plan/apply/rollback over HTTP under a service principal. |
| Engine (`backend/function-app/Modules/CcAlm/`) | The compare/plan/write/rollback logic, in PowerShell. The Function App and the CLI both call it, so there is one implementation, not two to keep in sync. |
| Local runner (`scripts/run-local.ps1`, `backend/local-runner/`) | The app plus the engine on your own machine, with a setup wizard that checks each client app registration step by step. No Azure. |
| CLI (`backend/cli/`) | Thin wrapper scripts (`compare.ps1`, `migrate.ps1`, `rollback.ps1`) over the same engine, for standalone or pipeline use without the Azure Function. |
| Build and deploy (`build.ps1`, `scripts/`) | Build the app, `pac code init`, `pac code push`. |
| Manifest (`config/manifest.json`) | Which tables move, in what order, and how records match. Columns and lookups come from each environment's metadata. |

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

## Or in XrmToolBox

The same compare, plan, dry run, apply, check afterwards and rollback as an [XrmToolBox](https://www.xrmtoolbox.com) tool, on your own XrmToolBox connections: no backend, no app registration. The engine is a C# port held to the same answers as the PowerShell one. Its review tree shows the configuration the way it is built - every record under the workstream, channel or queue it belongs to, with what each one uses listed where it is used - so what moves with what is visible before you tick anything. See [docs/xrmtoolbox.md](docs/xrmtoolbox.md).

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

Run it on your own machine against a client's environments, with only the app registrations they give you (no Azure, no connector). The quickest way: download **ContactCenterALM-LocalRunner.exe** from the [localrunner release](https://github.com/peterruiter/d365-contactcenter-alm/releases/tag/localrunner) and double-click it. Nothing to install, not even PowerShell 7. The same release has a zip that runs on an installed PowerShell 7, for laptops whose endpoint protection blocks the exe. From a clone:

```powershell
./scripts/run-local.ps1 -Profile contoso
```

The browser opens on a Setup wizard: enter each environment's app registration and run the checks one by one. Details in [docs/local-runner.md](docs/local-runner.md).

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
- Rollback restores changed records and deletes the ones a run created. It cannot reverse every provisioning side-effect: what Dataverse refuses to delete is listed.
- After an apply the engine compares again and reports each written record that does not match the source, so "it looked fine but wasn't" shows up in the run instead of in Test.
- Dependencies are checked before anything runs. A record whose parent, template or embedded reference is not in the target is added to the plan automatically, or shown as blocked with an "Add …" fix. Records pointing at a table written later (a workstream's default queue) are linked in a final pass. A dry run simulates the IDs it would create, so it reports exactly what an apply would do.
- Operating-hours calendar association is a second pass, not yet wired to a live org.
- Some entity set names (quick replies, tags) need confirming per org. The manifest notes them.

## Repository layout

| Path | Contents |
| --- | --- |
| `app/` | The code app. `src/ui` (the Capgemini design-system components, tokens and fonts), `src/pages`, `src/components`, `src/hooks/useMigration.ts` (the flow), `src/services` (mock, backend, connector, local runner), `src/types`. |
| `config/manifest.json` | Tables, order, stages, match keys, exclusions, detect-only rules. See [docs/manifest.md](docs/manifest.md). |
| `backend/function-app/` | The backend: PowerShell Azure Function wrapping the engine (`Modules/CcAlm`). |
| `backend/cli/` | The same engine as a command-line tool, for pipelines. |
| `backend/local-runner/` | Local web server, profile store and setup checks behind `scripts/run-local.ps1`. |
| `connector/` | Custom connector definition (OpenAPI + Entra auth). |
| `scripts/` | `deploy.ps1`, `init-app.ps1`, `deploy-backend.ps1`, `run-local.ps1`, `build-runner-release.ps1`, `test.ps1`, `record-fixture.ps1`, `make-icons.ps1`. |
| `xrmtoolbox/` | The XrmToolBox tool: the engine in C# (`CcAlm.Core`), the tool (`CcAlm.XrmToolBox`), and their tests. See [docs/xrmtoolbox.md](docs/xrmtoolbox.md). |
| `tests/` | Offline Pester tests: unit tests, a synthetic Dev and Test on the real schema, and replays of recorded environments. See [docs/testing.md](docs/testing.md). |
| `Start-LocalRunner.cmd` | Double-click launcher for the local runner. |
| `runner-exe/` | The local runner as one self-contained exe (.NET 10 + PowerShell 7 SDK). |
| `build.ps1` | Install, typecheck, build the app. |
| `docs/` | [getting-started](docs/getting-started.md), [architecture](docs/architecture.md), [setup](docs/setup.md), [usage](docs/usage.md), [usage (CLI/engine reference)](docs/usage-engine-reference.md), [backend](docs/backend.md), [local runner](docs/local-runner.md), [manifest](docs/manifest.md), [backend service principal](docs/backend-service-principal.md), [testing](docs/testing.md), [XrmToolBox tool](docs/xrmtoolbox.md) |

## Roadmap

- [x] Backend service (PowerShell Azure Function) wrapping the engine
- [x] Custom connector definition for the backend
- [x] Connector adapter wired into the app (published app calls the backend through the connector)
- [x] Published and running inside Dynamics against a real environment, end to end
- [x] Background runs with live progress
- [x] Check after every apply that the target matches the source
- [x] Offline regression tests on synthetic and recorded environments
- [ ] Manual-match override for records the engine cannot pair on name
- [ ] Operating-hours calendar-row copy wired to a live org

## Credits and licence

Table set and sequence follow Microsoft's [Contact Center configuration migration docs](https://learn.microsoft.com/en-us/dynamics365/customer-service/administer/migrate-channel-config-using-solutions). Sits next to [d365-conversation-diagnostics](https://github.com/peterruiter/d365-conversation-diagnostics), same idea: take the painful part out of CMT and Azure and put it somewhere a consultant can run it.

MIT.
