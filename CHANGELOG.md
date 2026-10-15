# Changelog

All notable changes to this project are recorded here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- **Local runner** (`scripts/run-local.ps1`). Runs the app and the engine on your own machine against a client's environments, with only the app registrations the client hands over: no Azure Function, no custom connector, nothing to create in Entra. A Setup tab takes each environment's URL, tenant ID, client ID and secret, then runs five checks one by one (tenant, sign-in, Application user, Contact Center installed, table access down to privilege depth), stopping at the first failure with what to ask the client for. The common AADSTS errors are translated, including the Secret-ID-instead-of-Value mistake. Environments that pass show up in Compare. One profile per client under `%LOCALAPPDATA%\CcAlm`, secrets encrypted with Windows DPAPI, nothing in the repo. See [docs/local-runner.md](docs/local-runner.md).
- **Per-environment app registrations.** Each environment in the registry can carry its own `tenantId` and `clientId` (falling back to the top-level ones), with secrets from `CCALM_CLIENT_SECRET_<ID>` before `CCALM_CLIENT_SECRET`. Works for the CLI and the Function too. `Connect-CcEnvironment` also takes the registry as an object, can connect a subset of environments, and can skip the WhoAmI probe.
- **Ready-built local runner zip** on the [localrunner release](https://github.com/peterruiter/d365-contactcenter-alm/releases/tag/localrunner): the app pre-built plus the engine and runner, started by double-clicking `Start-LocalRunner.cmd`. Needs PowerShell 7 and nothing else - no Node.js, no npm, no git - for laptops where `npm install` cannot reach the registry. `scripts/build-runner-release.ps1` builds it.
- `run-local.ps1` on Windows PowerShell 5.1 now says to install PowerShell 7, and how, instead of failing on a `#Requires` line.

### Changed
- The Function's labels and response mappers moved from `profile.ps1` into `backend/function-app/Contract.ps1`, shared with the local runner so both return the same shapes.

## [0.2.0](https://github.com/peterruiter/d365-contactcenter-alm/releases/tag/v0.2.0) - 2026-08-30

Table-by-table live testing against real Dev/Test environments turned up a run of write-path and matching bugs, plus a Zodiak-branded UI pass. Grouped by what actually changed for a user running a migration.

### Fixed
- **Alternate-key upsert failures** (e.g. operating hours 400 "key in request URI is not valid"). The write engine no longer builds upsert URLs from a Dataverse alternate key, which is org-specific metadata that may not be registered even when the manifest names one. It decides create vs. update purely from the natural-key match already found during compare.
- **`msdyn_uniquename` cannot be NULL** on `msdyn_routingconfiguration`, `msdyn_routingconfigurationstep`, `msdyn_assignmentconfiguration`, `msdyn_assignmentconfigurationstep`, `msdyn_capacityprofile`, `msdyn_notificationtemplate`, `msdyn_sessiontemplate` - a `SystemRequired` column that was never in `select`, so never written. Found the rest of this class by auditing every manifest table's entity metadata for `SystemRequired` + `IsValidForCreate` columns missing from `select`; `ratingmodel` was also missing `minratingvalue`/`maxratingvalue` the same way.
- **`msdyn_routingconfiguration` matching.** Its manifest lookup named an attribute that does not exist on the entity (confirmed against `EntityDefinitions`); its real lookup is `msdyn_liveworkstreamid`. Its match key also collided across workstreams (every workstream auto-gets an identically-named "Contact center routing configuration" record) until the workstream lookup joined the key. `ratingvalue` had the same class of bug: its match key named a lookup column (`ratingmodelid`) that never matched anything real (`_ratingmodelid_value` does).
- **Duplicate decision-ruleset writes.** The second ("double") write that lands ruleset dependency mappings was reusing the original (null-on-create) target GUID, re-POSTing the same record and hitting a duplicate-key rejection even though the first write had already succeeded.
- **Cross-environment matching for lookup-based match keys.** `msdyn_routingconfiguration`, `msdyn_assignmentconfiguration`, and their step/join tables match partly on a lookup column (e.g. name plus parent workstream). The engine's cross-environment key map used to build that key from the *raw, unresolved* GUID, which is different in every environment even for "the same" parent, so it could never agree between source and target. Every key used for cross-environment matching, embedded-GUID remapping, and rollback snapshotting is now the fully resolved natural key consistently.
- **Doomed writes aborting the whole run.** A ruleset referencing a queue not yet in target, or a step whose parent config is not in target, used to hard-fail the write and abort every later stage. That record is now skipped with a clear warning naming what it needs, and the run continues. A dependency now created earlier in the *same* run (a queue in stage 4) is immediately resolvable by whatever references it later (a ruleset in stage 6) - no second apply required.
- **Run status hid partial skips.** A run with skipped records used to report `Succeeded`. It now reports `PartiallyFailed` whenever anything did not move, distinct from a hard write failure.
- **Duplicate queue creation.** `msdyn_isomnichannelqueue` was excluded from the write payload, so every queue this tool created defaulted to `false` in Dataverse - which then made it invisible to the next compare's personal-queue filter, causing every subsequent apply to create another duplicate instead of recognizing the one it had just made.
- **Notification templates and other "managed" noise.** Records shipping with a managed solution (`ismanaged = true`) are excluded from compare and write across the 19 tables that carry the column - Dataverse rejects a raw write of one outright, and the field-diff noise from ~100% managed tables was masking real config.
- Vite dev server silently drifting to port 3001 when 3000 was taken, which broke the Function App's exact-origin CORS allow-list and surfaced as an opaque "Failed to fetch". `strictPort: true` now fails loudly instead.
- Light-mode theme toggle had insufficient contrast (dark text/icon on the blue header). Fixed by nesting a dedicated dark-themed `FluentProvider` around just that control instead of guessing at Fluent's internal class names.
- A composite match key (`table|matchKey`, and `matchKey` itself often containing `|`) was truncated by splitting on every `|` instead of just the first one, silently corrupting the rebuilt selection sent to Plan for any composite-key table.

### Added
- **Dependency graph now covers embedded GUIDs**, not just explicit lookup columns - a ruleset's `msdyn_rulesetdefinition` references (queues, workstreams, whatever it points at) show up as "Requires" hints and get auto-selected alongside the record, the same as an explicit lookup dependency already did.
- **Friendly display names.** Records with a name field (decision contracts, rulesets, workstreams, routing/assignment configs, context variables) show that name as the heading, with the technical match key underneath in small text. Tables with no name field of their own (routing/assignment steps) get a template label like "Step 10".
- Personal/system queues (one auto-provisioned per user by Dataverse) are always excluded from compare - never a real migration candidate, so there is no toggle to second-guess.
- All 10 plan stages now show in the plan panel, including ones with nothing to move, instead of only the stages that happened to have operations.
- Capgemini Zodiak brand and design system applied throughout the app (colours, type, spacing, logo).
- **Branding is now swappable.** `app/src/brands/` holds one file per visual identity (logo, favicon, page title, Fluent color ramp, footer); `VITE_BRAND` picks one at build time. Power Pete (purple/lilac) is the default so a clone with no `.env` looks right out of the box; set `VITE_BRAND=capgemini` for the Zodiak identity. Same idea as the brand-switching in the sibling `d365-contactcenter-estimator` project, adapted to a single build instead of one HTML file per brand.
- **Footer**, per brand: icon and site link, a one-line "not a Microsoft-supported path, dry-run first" disclaimer, and a creator/contact line (mail, Teams chat, a third link) - mirrors the footer structure in `d365-contactcenter-estimator`.
- Wizard-style floating side panel showing live compare/plan/run progress, so scrolling to the top is not needed to see whether something is happening.
- Full-width layout with horizontal-scroll fallback per section, and a CSS fix (`minmax(0, 1fr)` / `min-width: 0` / `overflow-wrap: anywhere`) so a long composite match key wraps instead of blowing out the grid and pushing the side panel out of the viewport.
- `build.ps1 -Deploy` builds and pushes the app in one call, reusing the current `pac auth` profile (or pass `-EnvironmentUrl` to select one first) - the quick path when iterating against one environment all session instead of running `build.ps1` then `deploy.ps1` separately.
- **Published inside Dynamics for the first time**: Easy Auth locked down the Function, the custom connector is created and wired (`generatedConnector.ts` maps the generated `ContactCenterALMService`), and `pac code push` deploys the app so it opens from Power Apps like any other app, calling the backend through the connector rather than a direct URL. Getting there took four Entra sign-in errors, each now documented with its fix in `docs/getting-started.md`'s "Published in Dynamics" section and troubleshooting table: `AADSTS90009` (client and resource are the same app - the resource must be the bare GUID, not `api://...`), `AADSTS90008` (missing the Graph `User.Read` delegated permission), `AADSTS50011` twice over (the generic consent redirect URI, then a second connector-specific one with a random suffix), and a `pac connector update` that reports success without actually changing the OAuth resource field on an already-created connector.
- Punchier header subtitle and footer disclaimer/creator copy, with a `.header-sub` overflow guard (ellipsis instead of wrapping out of the fixed-height header) since the new copy pushed closer to the line-length edge.

## [0.1.0] - 2026-08-05

First cut. A Power Apps code app for the UI, a reference engine for the cross-environment logic, and build and deploy scripts.

### Added
- **Code app** (`app/`): React, TypeScript, Vite, Fluent UI v9, `@microsoft/power-apps` SDK.
  - Environment picker, diff summary cards, diff view grouped by table with field deltas and selection, detect-only panel, ordered plan by stage, run progress with warnings, apply dialog with a Prod approval gate, rollback.
  - `AlmService` interface with two adapters: `mock` (in-memory sample data, runs standalone) and `backend` (calls the API contract). Swap by env var.
  - Host handshake via `setConfig` + `getContext`.
- **Backend** (`backend/function-app/`): PowerShell Azure Function wrapping the engine, with the six contract endpoints, blob-persisted run records and snapshots, and a stateless apply that rebuilds context from source and target.
- **Engine** (`backend/function-app/Modules/CcAlm/`): compare, plan, write, rollback. Shared by the Function and the CLI (`backend/cli/`).
- **Custom connector** (`connector/`): OpenAPI definition plus Entra OAuth properties.
- **Connector adapter** (`app/src/services/connectorAlmService.ts`): the published app calls the backend through the generated connector client. Three data sources now: `mock`, `backend` (local direct HTTP), `connector` (published).
- **Build and deploy**: `build.ps1`, `scripts/init-app.ps1`, `scripts/deploy.ps1` using the Power Platform CLI.
- **Manifest** (`config/manifest.json`): 24 tables plus detect-only rules, as data.
- Docs: architecture, setup, usage, backend, manifest, backend service principal.
- CI: app typecheck and build, reference-engine lint.

### Known limits
- Apply runs synchronously in the Function. A large Prod migration can approach the HTTP timeout; move Apply to Durable Functions to remove that. The polling contract already supports it.
- Operating-hours calendar-row copy is a second-pass hook, not yet wired to a live org.
- Async provisioning has no done signal; the engine polls with a timeout and warns.
- Rollback does not reverse provisioning side-effects.
- Writing routing config through the Web API is not a Microsoft-supported path and can break on a product update.
