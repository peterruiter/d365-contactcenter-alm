# Backend

The backend does the cross-environment work the code app cannot: read four environments, diff, plan, write, and roll back under a service principal. It is a PowerShell Azure Function that wraps the engine in `backend/function-app/Modules/CcAlm`. Same engine the CLI uses.

## Why PowerShell Functions

The engine already exists and is tested. Wrapping it in HTTP triggers reuses it as-is instead of porting it to another language. The `Modules/CcAlm` module is the single source of the compare, plan, write, and rollback logic. The HTTP functions are a thin layer: parse the request, call the engine, shape the response.

## Endpoints

| Route | Method | Function | Does |
| --- | --- | --- | --- |
| `/api/environments` | GET | GetEnvironments | Returns the registry, no secrets. |
| `/api/compare` | POST | Compare | Connects, diffs source against target, returns the diff. |
| `/api/plan` | POST | Plan | Rebuilds context, returns the ordered plan. |
| `/api/apply` | POST | Apply | Rebuilds context, runs the plan, persists the run and snapshot. |
| `/api/run/{id}` | GET | GetRun | Returns a stored run record. |
| `/api/run/{id}/rollback` | POST | Rollback | Restores from the run snapshot. |

## Stateless by design

The engine holds a read cache and a translation map in memory during a run. HTTP calls do not share memory, so compare, plan, and apply each rebuild that context from source and target. Apply takes the source, target, and selection, not a stored plan id, so nothing has to persist between the plan call and the apply call.

Two things do persist, in blob storage (the Function's own storage account):

- **Run records** (`run-{id}.json`): so `GET /run/{id}` works after the apply call returns.
- **Snapshots** (`snapshot-{id}.json`): so rollback can restore.

## Auth

Two separate identities, kept apart:

- **User to backend.** The code app calls the backend through a custom connector using Entra OAuth. Turn on App Service Authentication (Easy Auth) with Entra ID on the Function app so it validates the caller.
- **Backend to Dataverse.** The Function uses the service principal (client credentials) to call each environment's Web API. Secret in Key Vault, referenced from the `CCALM_CLIENT_SECRET` app setting.

## Settings

| Setting | Purpose |
| --- | --- |
| `CCALM_ENVIRONMENTS` | The environments registry JSON (tenant, client id, environments). |
| `CCALM_CLIENT_SECRET` | Service principal secret. Use a Key Vault reference. |
| `CCALM_RUNS_CONTAINER` | Blob container for runs and snapshots. Default `ccalm-runs`. |
| `AzureWebJobsStorage` | Function storage, also used for run and snapshot blobs. |

The deploy script copies `config/manifest.json` into the app and the engine picks it up from there.

## Deploy

```powershell
./scripts/deploy-backend.ps1 -ResourceGroup rg-ccalm -FunctionApp ccalm-func-nl -Location westeurope -EnvironmentsFile ./environments.json
```

Then:

1. Enable Easy Auth (Entra ID) on the Function app.
2. Create the custom connector from `./connector` (`pac connector create`), with the Function hostname in the swagger and the Entra app details in the properties.
3. In the code app: `pac code add-data-source` for that connector, set `VITE_ALM_SOURCE=backend`, and point `VITE_ALM_BACKEND_URL` at the Function while testing directly.

## Limits worth knowing

- **Apply runs synchronously.** For a big Prod migration this can approach the HTTP timeout. If you hit it, move Apply to Durable Functions so it runs in the background and the app polls `GET /run/{id}`. The contract already supports polling; only the Apply function changes.
- **Cold start.** PowerShell Functions and the `Az.Storage` dependency add cold-start time. An Elastic Premium plan removes it if that matters.
- Everything the engine cannot do still stands: no supported path for routing-config writes, no async provisioning done-signal, no clean reversal of provisioning side-effects. See `architecture.md`.
