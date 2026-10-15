# Local runner

Run the whole tool on your own machine, against a client's environments, with only the app registrations the client gives you. No Azure Function, no custom connector, no Entra changes on your side.

```
Browser (localhost:7171)  ──▶  scripts/run-local.ps1  ──▶  Client Dev / Test / Prod
   Setup + Compare UI           engine, in PowerShell        Dataverse Web API, as each app registration
```

The runner is a small web server in a PowerShell session. It serves the same app and runs the same engine the Azure Function does, so compare, plan, dry run, apply and rollback behave identically.

## What you need from the client

Per environment (one app registration can cover several):

| Value | Where the client finds it |
| --- | --- |
| Environment URL | Power Platform admin center -> the environment -> Environment URL, e.g. `https://contoso-dev.crm4.dynamics.com` |
| Directory (tenant) ID | App registration -> Overview |
| Application (client) ID | App registration -> Overview |
| Client secret **Value** | App registration -> Certificates & secrets. Shown once, when created. Not the Secret ID. |

And the app registration has to be an **Application user** in each environment, with System Administrator or a custom role with organization-level create, read, write and delete on the Contact Center tables. The client does that in the Power Platform admin center -> environment -> Settings -> Users + permissions -> Application users.

## Prerequisites

- Windows, PowerShell 7.2 or later (`pwsh`)
- Node.js LTS (only to build the app, which the script does for you)

## Run it

```powershell
./scripts/run-local.ps1 -Profile contoso
```

The first run installs the app's packages and builds it (a minute). Then the browser opens on **Setup**.

Use one profile per client. Each profile has its own environments and secrets, so client A's Prod never shows up while you work for client B.

## Setup: one environment at a time

1. **App registration.** Enter the name, URL, tenant ID, client ID and secret. If the client uses one app registration for several environments, pick it under **Same app registration as** and skip the IDs and secret.
2. **Checks.** Runs in order and stops at the first failure, with what to ask the client for:

| Check | Proves | Typical failure |
| --- | --- | --- |
| Tenant | The tenant ID is a real tenant | Typo in the tenant ID |
| Sign in | Client ID and secret get a token for this environment | `AADSTS7000215` (Secret ID entered instead of the Value), `7000222` (expired), `700016` (wrong client ID or tenant) |
| Application user | The app registration is an enabled Application user, with a role | Not added to this environment, or no security role |
| Contact Center | Contact Center is installed; workstreams and queues are readable | Wrong environment |
| Table access | Read on every table, create/update/delete privileges at organization level | Custom role missing tables, or Business Unit-level privileges |

An environment that passes (warnings are fine) shows up in **Compare**. Changing its URL, IDs or secret clears the checks, so they run again.

## Where things are stored

`%LOCALAPPDATA%\CcAlm\<profile>\`

- `registry.json`: URLs, IDs, check results, and the secret encrypted with Windows DPAPI. Only your Windows user on this machine can decrypt it. Copying the file to another machine or user does not carry the secrets; the wizard asks for them again.
- `runs\`: run records and the snapshots rollback uses.

Nothing goes into the repo.

## Options

| Parameter | Default | |
| --- | --- | --- |
| `-Profile` | `default` | Which client's set of environments |
| `-Port` | `7171` | Local port |
| `-Rebuild` | off | Rebuild the app even if it looks current |
| `-NoBrowser` | off | Do not open the browser |

Working on the app itself? Run the runner, then `npm run dev:runner` in `app`: Vite on port 3000 with hot reload, proxying `/api` to the runner.

## Security notes

- The runner listens on `localhost` only.
- Every API call needs a custom header that only the runner's own page sends, so another website open in the same browser cannot call it.
- Secrets travel from the browser to the runner over loopback and are never sent back. The setup screen only shows whether one is saved.
- Writes run under the client's app registration, with whatever rights they gave it. A Prod environment with **Approval** on still needs the explicit tick before Apply.

## Same engine, outside the runner

The registry format behind this also works for the CLI and the Azure Function: each environment in `environments.json` can carry its own `tenantId` and `clientId`, falling back to the top-level ones. Secrets per environment come from `CCALM_CLIENT_SECRET_<ID>` (for example `CCALM_CLIENT_SECRET_PROD`), then `CCALM_CLIENT_SECRET`.
