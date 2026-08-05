# Setup: service principal and app users

The engine runs as one service principal, registered as an Application User in every environment you touch. This page gets you there. Budget 20 to 30 minutes the first time.

## 1. Register the app in Entra

1. Entra admin centre -> App registrations -> New registration.
2. Name it something like `cc-alm-runner`. Single tenant.
3. No redirect URI. This is a daemon, not an interactive app.
4. Copy the **Application (client) ID** and the **Directory (tenant) ID**.

## 2. Add a client secret

1. Certificates & secrets -> New client secret.
2. Set an expiry your org allows. Copy the **value** now. You cannot read it again.
3. Store it wherever you keep secrets. At run time it goes in `CCALM_CLIENT_SECRET`.

You do not need Dataverse API permissions on the app registration itself. The Application User in each environment is what grants access.

## 3. Create an Application User in every environment

Do this in Dev, Test, Acc, and Prod. Each is separate.

1. Power Platform admin centre -> pick the environment -> Settings -> Users + permissions -> Application users.
2. New app user -> Add an app -> paste the client ID.
3. Pick a business unit.
4. Assign security roles. See below.

## 4. Privileges

The app user needs read and write on the manifest tables. Two options.

**Least privilege (recommended for Prod).** Build a custom security role with Create, Read, Write on the tables in `config/manifest.json`, at organisation scope. That is workstreams, queues, operating hours, capacity profiles, rating models and values, characteristics, decision contracts and rulesets, routing and assignment configs and their steps, channel settings, quick replies, tags, context variables, and the omnichannel configuration. Read on entity metadata (`EntityDefinitions`), which the write engine needs for navigation properties.

**Fast (fine for Dev and Test).** Assign **System Administrator**. Simple, and too broad for Prod.

## 5. Confirm it works

```powershell
Import-Module ./src/CcAlm/CcAlm.psd1
$env:CCALM_CLIENT_SECRET = '<secret value>'
$envs = Connect-CcEnvironment -ConfigPath ./environments.json -Verbose
```

`Connect-CcEnvironment` runs a `WhoAmI` against each environment. If one fails, the message tells you which environment and usually why: a missing app user, a missing role, or a wrong URL.

## Notes

- **Prod gets `requireApproval: true` in the registry.** With that set, `Invoke-CcPlan -Mode Apply` refuses to run against Prod unless you pass `-Approved`. That is a governance gate, not a CMT step.
- **Rotate the secret on schedule.** The engine reads it fresh each run from the environment variable, so rotation is just updating the variable.
- **One app registration, many environments.** You do not need a registration per environment. One app user per environment, one shared app registration.
