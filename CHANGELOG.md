# Changelog

All notable changes to this project are recorded here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.1.0] - 2026-08-05

First cut. A Power Apps code app for the UI, a reference engine for the cross-environment logic, and build and deploy scripts.

### Added
- **Code app** (`app/`): React, TypeScript, Vite, Fluent UI v9, `@microsoft/power-apps` SDK.
  - Environment picker, diff summary cards, diff view grouped by table with field deltas and selection, detect-only panel, ordered plan by stage, run progress with warnings, apply dialog with a Prod approval gate, rollback.
  - `AlmService` interface with two adapters: `mock` (in-memory sample data, runs standalone) and `backend` (calls the API contract). Swap by env var.
  - Host handshake via `setConfig` + `getContext`.
- **Reference engine** (`backend/reference-engine-powershell/`): compare, plan, write, rollback under a service principal. The spec for the backend.
- **Build and deploy**: `build.ps1`, `scripts/init-app.ps1`, `scripts/deploy.ps1` using the Power Platform CLI.
- **Manifest** (`config/manifest.json`): 24 tables plus detect-only rules, as data.
- Docs: architecture, setup, usage, manifest, backend service principal.
- CI: app typecheck and build, reference-engine lint.

### Known limits
- Backend service (Azure Function) not built yet. The app runs on mock data and the backend adapter is wired to the contract, ready to point at it.
- Operating-hours calendar-row copy is a second-pass hook, not yet wired to a live org.
- Async provisioning has no done signal; the engine polls with a timeout and warns.
- Rollback does not reverse provisioning side-effects.
- Writing routing config through the Web API is not a Microsoft-supported path and can break on a product update.
