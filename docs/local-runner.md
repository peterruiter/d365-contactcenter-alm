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

## Get it running

Two ways in. The zip is the one to hand to a colleague.

### Option 1: the ready-built zip (nothing else to install)

1. Install PowerShell 7 if you do not have it: `winget install --id Microsoft.PowerShell -e`. Windows ships with PowerShell 5.1, which is not enough.
2. Download **ContactCenterALM-LocalRunner.zip** from the [localrunner release](https://github.com/peterruiter/d365-contactcenter-alm/releases/tag/localrunner) and unzip it.
3. Double-click **Start-LocalRunner.cmd** and type a profile name.

The app comes pre-built, so no Node.js, no npm and no access to the npm registry. That matters on locked-down client laptops and behind corporate proxies, where `npm install` tends to fail with `ECONNRESET` or `EPERM`.

### Option 2: from a clone of the repo

Needs PowerShell 7 and Node.js LTS, plus network access to the npm registry.

```powershell
./scripts/run-local.ps1 -Profile contoso
```

The first run installs the app's packages and builds it (a minute). After that it rebuilds only when the app source changes. Either way the browser opens on **Setup**.

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
| `-Rebuild` | off | Rebuild the app even if it looks current (repo clone only) |
| `-NoBrowser` | off | Do not open the browser |

Working on the app itself? Run the runner, then `npm run dev:runner` in `app`: Vite on port 3000 with hot reload, proxying `/api` to the runner.

## Building the release zip

```powershell
./scripts/build-runner-release.ps1
gh release upload localrunner ./out/ContactCenterALM-LocalRunner.zip --clobber
```

It builds the app in runner mode and zips it with the engine, the runner and the launcher, in the repo's own folder layout. The zip leaves out the app source, which is how `run-local.ps1` knows never to build.

## Security notes

- The runner listens on `localhost` only.
- Every API call needs a custom header that only the runner's own page sends, so another website open in the same browser cannot call it.
- Secrets travel from the browser to the runner over loopback and are never sent back. The setup screen only shows whether one is saved.
- Writes run under the client's app registration, with whatever rights they gave it. A Prod environment with **Approval** on still needs the explicit tick before Apply.

## Same engine, outside the runner

The registry format behind this also works for the CLI and the Azure Function: each environment in `environments.json` can carry its own `tenantId` and `clientId`, falling back to the top-level ones. Secrets per environment come from `CCALM_CLIENT_SECRET_<ID>` (for example `CCALM_CLIENT_SECRET_PROD`), then `CCALM_CLIENT_SECRET`.
