# Changelog

All notable changes to this project are recorded here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.1.0] - 2026-08-05

First cut. A Power Apps code app for the UI, a reference engine for the cross-environment logic, and build and deploy scripts.

### Added
- **Code app** (`app/`): React, TypeScript, Vite, Fluent UI v9, `@microsoft/power-apps` SDK.
  - Environment picker, diff summary cards, diff view grouped by table with field deltas and selection, detect-only panel, ordered plan by stage, run progress with warnings, apply dialog with a Prod approval gate, rollback.
  - `AlmService` interface with two adapters: `mock` (in-memory sample data, runs standalone) and `backend` (calls the API contract). Swap by env var.
  - Host handshake via `setConfig` + `getContext`.
- **Backend** (`backend/function-app/`): PowerShell Azure Function wrapping the engine, with the six contract endpoints, blob-persisted run records and snapshots, and a stateless apply that rebuilds context from source and target.
- **Engine** (`backend/function-app/Modules/CcAlm/`): compare, plan, write, rollback. Shared by the Function and the CLI (`backend/cli/`).
- **Custom connector** (`connector/`): OpenAPI definition plus Entra OAuth properties, so the code app calls the backend through a governed connector.
- **Build and deploy**: `build.ps1`, `scripts/init-app.ps1`, `scripts/deploy.ps1` using the Power Platform CLI.
- **Manifest** (`config/manifest.json`): 24 tables plus detect-only rules, as data.
- Docs: architecture, setup, usage, backend, manifest, backend service principal.
- CI: app typecheck and build, reference-engine lint.

### Known limits
- Apply runs synchronously in the Function. A large Prod migration can approach the HTTP timeout; move Apply to Durable Functions to remove that. The polling contract already supports it.
- The code app still calls the backend via direct fetch. Swap to the generated connector client after `pac code add-data-source`.
- Operating-hours calendar-row copy is a second-pass hook, not yet wired to a live org.
- Async provisioning has no done signal; the engine polls with a timeout and warns.
- Rollback does not reverse provisioning side-effects.
- Writing routing config through the Web API is not a Microsoft-supported path and can break on a product update.
