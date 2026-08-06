# Getting started

This takes you from nothing to a working tool, one step at a time. You do not need prior Power Platform or Azure knowledge. Follow it top to bottom. After each phase there is a check that tells you it worked before you move on.

There are two milestones:

- **Milestone A: run the app on sample data.** About 10 minutes. No accounts, no cloud. Good for seeing what the tool does.
- **Milestone B: run it against your real environments.** A few hours. Needs admin rights in Power Platform and an Azure subscription.

Do A first. It proves the app works on your machine before you touch anything real.

Anything in `ANGLE_BRACKETS` is a value you replace with your own.

---

# Milestone A: run the app on sample data

## A1. Install Node.js

1. Go to https://nodejs.org and download the LTS version.
2. Run the installer, accept the defaults.
3. Open a new terminal (PowerShell on Windows) and check it:

```powershell
node --version
```

**Check:** you see a version like `v20.x` or `v22.x`. If "node is not recognized", close the terminal, open a new one, and try again.

## A2. Get the code

If you have the zip:

```powershell
cd ~\source\repos
# unzip d365-contactcenter-alm.zip here so you get a d365-contactcenter-alm folder
cd d365-contactcenter-alm
```

## A3. Start the app

```powershell
cd app
npm install
npm run dev
```

The first `npm install` downloads the libraries and takes a minute or two. That is normal.

**Check:** the terminal prints a line like `Local: http://localhost:3000`. Open that address in your browser. You see the Contact Center ALM app with sample environments (Dev, Test, Acc, Production). Pick Dev as source and Test as target, hit Compare, and you see a diff with workstreams, queues, and routing rulesets. Click through: build a plan, dry run, apply. This is sample data, so nothing real changes.

That is Milestone A. The app works. To stop it, press `Ctrl+C` in the terminal.

If you only wanted to see the tool, you can stop here. To make it work against your environments, carry on.

---

# Milestone B: run it against your real environments

This has more moving parts, so here is the order before the detail. Do them in this order. Each one depends on the ones before it.

| Phase | What you do | Why |
| --- | --- | --- |
| B1 | Install four command-line tools | You need them to deploy |
| B2 | Create an app registration in Entra | The tool's identity |
| B3 | Add that identity to each environment | So it can read and write config |
| B4 | Turn on Code Apps in the environment | So the app can be published there |
| B5 | Fill in your environment list | So the tool knows your URLs |
| B6 | Deploy the backend to Azure | The engine that does the work |
| B7 | Test the backend on its own | Prove it reaches your environments |
| B8 | Point the app at the backend | Connect the two |
| B9 | Do a first safe run: Dev to Test | Confirm end to end |

You need: an account that can create app registrations in Entra, System Administrator (or equivalent) in each Dynamics environment, and an Azure subscription you can create resources in. If you do not have these, ask whoever runs your tenant.

---

## B1. Install the tools

Install these four. After each, open a new terminal and run the check.

**Azure CLI** (creates the cloud resources):
- Download from https://aka.ms/installazurecliwindows and run it.
- Check: `az --version`

**Azure Functions Core Tools** (publishes the backend):
- Download from https://go.microsoft.com/fwlink/?linkid=2174087 (v4, x64) and run it.
- Check: `func --version` shows a `4.x` number.

**Power Platform CLI** (publishes the app):
- Easiest way: `dotnet tool install --global Microsoft.PowerApps.CLI.Tool`. If you do not have .NET, install the standalone from https://aka.ms/PowerPlatformCLI.
- Check: `pac help`

**PowerShell 7** (runs the deploy scripts):
- Windows 10/11 has PowerShell 5 built in, which is fine for the scripts, but 7 is better. Get it from https://aka.ms/powershell-release?tag=stable.
- Check: `pwsh --version` (or use the built-in `powershell`).

**Check for the phase:** all four commands above print a version or help text with no error.

---

## B2. Create the app registration (the tool's identity)

This is the identity the backend uses to read and write your environments. You do this once.

1. Go to https://entra.microsoft.com and sign in.
2. In the left menu: **Identity -> Applications -> App registrations**. If the menu looks different, search "App registrations" in the top search bar.
3. Click **New registration**.
   - Name: `cc-alm-runner`
   - Supported account types: **Accounts in this organizational directory only**
   - Leave Redirect URI blank.
   - Click **Register**.
4. On the app's Overview page, copy these two values into a notepad:
   - **Application (client) ID**
   - **Directory (tenant) ID**
5. In the left menu of the app: **Certificates & secrets -> Client secrets -> New client secret**.
   - Description: `ccalm`
   - Expires: pick your org's allowed period.
   - Click **Add**.
   - Copy the **Value** now (not the Secret ID). You cannot see it again after you leave the page. Put it in your notepad.

**Check:** you have three values written down: tenant ID, client ID, and the secret value.

---

## B3. Add the identity to each environment

The app registration exists, but it cannot touch any environment yet. You add it as an Application User in each one. Repeat this for **every** environment you want to compare (Dev, Test, Acc, Prod).

1. Go to https://admin.powerplatform.microsoft.com
2. **Environments** -> click the environment (start with Dev).
3. **Settings** (top bar) -> **Users + permissions** -> **Application users**.
4. Click **New app user**.
5. Click **Add an app**, paste the **client ID** from B2, select it, click **Add**.
6. Set a **Business unit** (the default root one is fine).
7. Under **Security roles**, click the pencil and add a role:
   - For Dev and Test, **System Administrator** is simplest.
   - For Acc and Prod, use a tighter role. The reference engine README lists the tables it needs. You can start with System Administrator to get working, then tighten later.
8. Click **Create**.

Repeat 2 to 8 for Test, then Acc, then Prod.

**Check:** each environment's Application users list shows `cc-alm-runner` with a security role.

---

## B4. Turn on Code Apps in the environment

The app is a "code app". The feature is off by default. Turn it on in the environment where you will publish it (usually Dev).

1. In https://admin.powerplatform.microsoft.com -> **Environments** -> your Dev environment.
2. **Settings** -> **Product** -> **Features**.
3. Find **Power Apps code apps** and switch it **On**.
4. Click **Save**.

**Check:** the toggle stays On after you save. Without this, the publish step in B8 fails quietly.

---

## B5. Fill in your environment list

Back in the code folder, make your own environment list from the template.

1. Copy the template to the repo root:

```powershell
cd ~\source\repos\d365-contactcenter-alm
Copy-Item .\config\environments.example.json .\environments.json
```

2. Open `environments.json` in an editor and fill in:
   - `tenantId`: your tenant ID from B2.
   - `clientId`: your client ID from B2.
   - Leave `clientSecret` as it is. You will set the secret separately, never in this file.
   - For each environment, set the real `url`. Find each URL in the Power Platform admin center on the environment's page (it looks like `https://yourorg.crm4.dynamics.com`). Delete environments you do not have.

**Check:** `environments.json` has your real tenant, client, and environment URLs. This file is git-ignored, so it will not be committed.

---

## B6. Deploy the backend to Azure

Now put the engine in the cloud.

1. Sign in to Azure:

```powershell
az login
```

A browser opens. Sign in. If you have more than one subscription, pick the right one:

```powershell
az account set --subscription "YOUR_SUBSCRIPTION_NAME"
```

2. Run the deploy script. Pick a globally unique name for `FunctionApp` (letters and numbers, e.g. `ccalmfuncYOURINITIALS`):

```powershell
.\scripts\deploy-backend.ps1 `
  -ResourceGroup rg-ccalm `
  -FunctionApp ccalmfuncYOURINITIALS `
  -Location westeurope `
  -EnvironmentsFile .\environments.json
```

This creates a resource group, a storage account, and the Function app, then publishes the code. It takes a few minutes. It will print a warning that you still need to set the secret. That is the next step.

3. Set the service principal secret on the Function (use the secret value from B2):

```powershell
az functionapp config appsettings set `
  --name ccalmfuncYOURINITIALS `
  --resource-group rg-ccalm `
  --settings "CCALM_CLIENT_SECRET=YOUR_SECRET_VALUE"
```

**Check:** the deploy script finishes and prints `Base URL: https://ccalmfuncYOURINITIALS.azurewebsites.net/api`. Copy that URL.

---

## B7. Test the backend on its own

Before wiring the app, confirm the backend reaches your environments.

> Heads up: right now the backend is open (no sign-in) because you have not turned on authentication yet. That is fine for this Dev test on your own machine. You lock it down in B8 before anyone else uses it. Do not share the URL yet.

1. Ask it for your environment list:

```powershell
curl https://ccalmfuncYOURINITIALS.azurewebsites.net/api/environments
```

**Check:** you get back JSON listing your environments (dev, test, and so on). If you do, the Function is running and reading your settings.

2. Run a real compare between two environments:

```powershell
curl -Method Post `
  -Uri https://ccalmfuncYOURINITIALS.azurewebsites.net/api/compare `
  -ContentType "application/json" `
  -Body '{"sourceEnvId":"dev","targetEnvId":"test"}'
```

**Check:** you get JSON with a `summary` and `tables`. That means the service principal signed in to both environments and read their config. If you get an error instead, see Troubleshooting at the bottom.

---

## B8. Point the app at the backend

You can run this two ways. Start with the local way, because it is quicker to confirm. Then do the published way for real use.

### Local (quickest to confirm)

The backend must accept calls from your local app. Allow it, then point the app at it.

1. Allow the local app to call the Function:

```powershell
az functionapp cors add `
  --name ccalmfuncYOURINITIALS `
  --resource-group rg-ccalm `
  --allowed-origins http://localhost:3000
```

2. Tell the app to use the backend. Create `app\.env` from the example:

```powershell
Copy-Item .\app\.env.example .\app\.env
```

Open `app\.env` and set:

```
VITE_ALM_SOURCE=backend
VITE_ALM_BACKEND_URL=https://ccalmfuncYOURINITIALS.azurewebsites.net/api
```

3. Restart the app:

```powershell
cd app
npm run dev
```

**Check:** open http://localhost:3000, pick Dev and Test, hit Compare. You now see your **real** config, not the sample data. That is the whole tool working end to end.

### Published in Dynamics (for real use)

This runs the app inside Dynamics, calling the backend through the custom connector. Six steps. Take them in order.

**Step 1. Lock the backend down.**
In the Azure portal, open the Function app -> **Settings -> Authentication -> Add identity provider -> Microsoft**. Accept the defaults. This creates an Entra app for the Function and makes it reject anonymous callers. Copy the **Application (client) ID** it creates and the **Application ID URI** (looks like `api://...`); you need them in step 2.

**Step 2. Create the custom connector.**
Open `connector\apiDefinition.swagger.json` and replace `REPLACE_WITH_FUNCTION_HOSTNAME` with `ccalmfuncYOURINITIALS.azurewebsites.net`. Open `connector\apiProperties.json` and fill in the `REPLACE_WITH_...` values (your tenant ID from B2, and the Function's Entra app client ID and App ID URI from step 1). Then:

```powershell
pac connector create --api-definition-file .\connector\apiDefinition.swagger.json --api-properties-file .\connector\apiProperties.json
```

Copy the connector's **API name** from the output (looks like `shared_contactcenteralm-xxxx`).

**Step 3. Create a connection to it.**
Go to https://make.powerapps.com -> **Connections** (left menu) -> **New connection** -> search for **Contact Center ALM** -> **Create**. Sign in when prompted. Then copy the connection's **ID**: open the connection and take the id from the browser URL (the long value after `/connections/`).

**Step 4. Initialise the app and add the connector as a data source.**

```powershell
.\scripts\init-app.ps1 -EnvironmentUrl https://yourorg-dev.crm4.dynamics.com
cd app
pac code add-data-source -a "API_NAME_FROM_STEP_2" -c "CONNECTION_ID_FROM_STEP_3"
```

This generates typed files under `app\src\generated\`. If you hit `Error: Invalid URI format`, open `app\power.config.json`, add `"region": "prod"`, save, and re-run the `add-data-source` command.

**Step 5. Wire the app to the generated client.**
Open `app\src\services\generatedConnector.ts`. It has two marked spots:
- Set the import at the top to the generated service. Look in `app\src\generated\services\` for the file (for example `ContactCenterAlmService.ts`) and import it.
- Delete the `throw` in `getGeneratedClient()` and uncomment the mapping just below it. The method names (`GetEnvironments`, `Compare`, and so on) match the generated service; adjust if the generator named them differently.

Then point the app at the connector. In `app\.env` set:

```
VITE_ALM_SOURCE=connector
```

Test it locally first, signed into your tenant, with the connector proxy running:

```powershell
# Terminal 1: the connector proxy (auth + routing)
cd app
pac code run

# Terminal 2: the app
cd app
npm run dev
```

**Check:** the app loads and Compare shows your real config, now going through the connector rather than a direct URL.

**Step 6. Publish.**

```powershell
cd ..
.\scripts\deploy.ps1 -EnvironmentUrl https://yourorg-dev.crm4.dynamics.com
```

**Check:** in https://make.powerapps.com -> **Apps**, you see Contact Center ALM. Open it. The first time, it asks you to allow the connection. Click **Allow**. Compare shows your real config. That is the full product, running inside Dynamics.

---

## B9. First safe run: Dev to Test

Never point a new tool at Prod first. Build trust on Test.

1. In the app, pick **Dev** as source and **Test** as target.
2. **Compare.** Read the diff. Missing and changed rows are what a move would write.
3. **Build plan.** Read the order. Parents come before the records that point at them.
4. **Run -> Dry run.** This writes nothing. Read the stages and any warnings.
5. **Run -> Apply.** This writes to Test. Watch the stage progress.
6. Open Test in Dynamics and confirm the config landed.
7. If something looks wrong, use **Roll back this run**. It restores Test from the snapshot the run took.

Once you trust it on Test, you can use Acc and Prod. Prod makes you tick an approval box before Apply.

---

# Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `npm run dev` says cannot find package.json | You are in the repo root, not `app` | `cd app` first |
| `pac` or `func` or `az` "not recognized" | Tool not installed, or terminal opened before install | Install it, open a new terminal |
| `/environments` returns an error | `CCALM_ENVIRONMENTS` not set | Re-run the deploy script, check `environments.json` is valid JSON |
| `/environments` returns 500 | `CCALM_ENVIRONMENTS` setting empty or malformed from CLI quoting | Set it via the Azure portal as one compact line (see below), then it works. A redeploy also ships a file fallback. |
| `/compare` returns "Could not reach ..." | App user missing in that environment, or wrong URL | Redo B3 for that environment, check the URL in `environments.json` |
| Compare in the app shows sample data, not real | `.env` still on mock, or app not restarted | Set `VITE_ALM_SOURCE=backend` in `app\.env`, restart `npm run dev` |
| Browser console shows a CORS error | Function does not allow localhost | Run the `az functionapp cors add` command in B8 |
| Publish (`pac code push`) does nothing | Code Apps feature is off | Redo B4, make sure the toggle saved |
| Deploy script: "az not found" | Azure CLI missing or not signed in | Install it, run `az login` |
| App error "Connector client not wired yet" | `VITE_ALM_SOURCE=connector` but step B8.5 not done | Wire `app\src\services\generatedConnector.ts`, or switch back to `mock`/`backend` |
| `pac code add-data-source`: "Invalid URI format" | Missing region in the app config | Add `"region": "prod"` to `app\power.config.json`, re-run |
| Connector calls fail when running locally | Connector proxy not running | Start `pac code run` in a second terminal, signed into your tenant |
| Published app: connector calls fail | Connection not authorised | Open the app, click **Allow** when prompted; check the connection exists under Connections |

If a portal menu has moved, use the search bar at the top of the portal for the bold names in each step. Microsoft changes menu labels often.
