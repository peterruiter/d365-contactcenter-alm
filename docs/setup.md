# Setup

Get the code app running, first on mock data, then against your environments.

## Prerequisites

- Node.js LTS and npm
- Power Platform CLI (`pac`): https://aka.ms/PowerPlatformCLI
- Code Apps enabled on the environment. Admin center -> Environments -> pick the environment -> Settings -> Product -> Features -> turn on Power Apps code apps. Without this, `pac code` commands fail silently.
- A Power Apps Premium license for anyone who runs the published app

## Run locally on mock data

No environment or backend needed. Good for a demo or UI work.

```bash
cd app
npm install
npm run dev
```

The app opens with sample workstreams, queues, and routing rulesets. Every screen works: compare, select, plan, dry-run, apply, roll back. Data source is `mock` by default (`app/.env` -> `VITE_ALM_SOURCE=mock`).

## Point it at the backend

Once the backend exists (see `architecture.md`, option A):

```bash
cd app
cp .env.example .env
# set VITE_ALM_SOURCE=backend and VITE_ALM_BACKEND_URL=<backend base url>
npm run dev
```

## Initialise the code app in an environment

One time per clone. This creates the code app config and wires the data source.

```powershell
./scripts/init-app.ps1 -EnvironmentUrl https://contoso-dev.crm4.dynamics.com
```

It runs `pac code init` and prints the `pac code add-data-source` command for your chosen backend variant.

## Deploy

Build and push to an environment:

```powershell
./scripts/deploy.ps1 -EnvironmentUrl https://contoso-dev.crm4.dynamics.com
```

That authenticates, selects the environment, builds the app, and runs `pac code push`. Open it from Power Apps -> Apps.

## Backend service principal

If you run option A, the backend needs one Entra app registration added as an Application User in every environment, with privileges on the manifest tables. That setup is in `backend-service-principal.md`.

## Note on the CLI

Microsoft is moving code app commands from `pac code` to an npm-based CLI shipped in `@microsoft/power-apps`. `pac code push` works today and is what the scripts use. When the npm CLI lands as the default, the deploy script is the only place to change.
