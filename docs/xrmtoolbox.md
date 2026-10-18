# XrmToolBox tool

**Contact Center ALM** for [XrmToolBox](https://www.xrmtoolbox.com) moves Dynamics 365 Contact Center configuration between two environments: workstreams with their routing configurations, work classification and route-to-queue rules, queues, rulesets, decision contracts, templates, capacity profiles, channels and agent content. It runs in XrmToolBox on your own connections, so there is nothing to deploy and no app registration to create: sign in the way you sign in for any other XrmToolBox tool.

It does what the Dynamics app and the local runner do, with the same rules and the same answers: records are matched by name, never by GUID; every dependency is checked before anything runs; a dry run shows exactly what an apply would do; an apply checks afterwards that the target now matches the source; and every apply can be rolled back.

## Install

**From the Tool Library** (once published): in XrmToolBox open **Tool Library**, search for *Contact Center ALM*, install.

**By hand**: download `ContactCenterALM-XrmToolBox.zip` from the [xrmtoolbox release](https://github.com/peterruiter/d365-contactcenter-alm/releases), close XrmToolBox, unzip the two DLLs into `%AppData%\MscrmTools\XrmToolBox\Plugins`, and start XrmToolBox again. The tool is unsigned; Windows may ask you to unblock the zip first (right-click, Properties, Unblock).

Needs XrmToolBox 1.2025.10 or later.

## Use it

1. Connect to the **source** environment the usual way and open **Contact Center ALM**.
2. **Choose target…** picks the second connection: the environment to move to.
3. **Compare** reads both. The Review tab shows every difference **by structure**: each record sits under the one it belongs to, grouped as Foundations, Workstreams, Queues, Routing, Channels and Agent content, and marked New, Changed, Ambiguous or Only in target (Same is hidden; tick it to see those too).

   ```
   Workstreams (3)
     Mortgage chat — workstream  [New] · 5 under it, 5 of 5 ticked
       Contact center routing configuration — routing configuration  [New] · 1 under it, 1 of 1 ticked
         Route to queue — routing step  [New]
           uses Mortgage route — ruleset  [New]
       uses Mortgage queue — queue  [New]
   ```

   A line marked **uses** is a record that lives elsewhere in the tree, shown where it is used, so the same queue appears under every step that routes to it and under its own group. A record used in more than one place says so. **Show: By table** gives one list per table instead.
4. **Select a record** to see what differs, what it needs, **where it is used** (what points at it, and through which column) and everything under it. A double-click on a row in any of those three lists goes to that record; the line under the title goes up to the record it sits in.
5. **Tick what to move.** Ticking a record also ticks everything under it and what that uses: a workstream brings its routing configuration, its work classification and route-to-queue steps, their rulesets, its queues, templates and the rest. Unticking takes them away again, except what another ticked record still needs. *Select all* above the tree works on what the filters and search show.
6. **Check the plan.** Opening the **Plan check** tab does it; the button in the toolbar does the same. It reads nothing from Dataverse - it works from what the compare read - so it is instant. Every ticked record is checked before anything is written: each of its parents, templates and embedded references must be in the target, be created earlier in the same run, or be linked at the end. Anything that cannot is blocked, with the reason, and a record that is only in the plan because something else needs it says which record that is. **Add what is missing** adds the records a blocked one needs. Back on the Review tab the tree then says how many blocked records sit under each workstream or channel.
7. **Dry run.** Goes through every write without writing anything. It reuses what the compare read, so it is fast. The **Run** tab says how many records are ready and has the button, and opening it checks the plan first if that has not happened yet.
8. **Apply.** Unlocks after a dry run of the same plan. It reads the target again first, so it never writes from an old picture, snapshots every record it changes, and ends by reading back everything it wrote. The Run tab then says the target matches the source, or lists each record that still differs with the setting and both values, and why when Dataverse is the reason. Records Dataverse created on its own during the run (the routing contract of a new workstream) are listed too.
9. **Roll back.** *Roll back this run* undoes the last apply; *Roll back a run…* any earlier one from its snapshot. Changed records get their settings and lookups back, created ones are deleted, children first.

Runs and snapshots are kept in `%AppData%\MscrmTools\XrmToolBox\Settings\ContactCenterALM\runs` (**Runs folder** opens it).

### Before you move

- **Record workstreams** (email, case) point at their table's record routing hub. Set up record routing for that table in the target first; the plan blocks the workstream otherwise. The hub's intake rules are not moved.
- **Per-environment set-up** - phone numbers, WhatsApp and SMS accounts, Copilot Studio agents - is listed under the Review tab's notes and stays a manual step.
- Templates and other records that come with a **managed solution** must be installed in the target; the plan says which.
- Writing Contact Center configuration through the API is not a Microsoft-supported path. Dry-run first, and try it on Dev and Test before Production.

## How it is built

| Path | |
| --- | --- |
| `xrmtoolbox/src/CcAlm.Core` | The engine in C# (.NET Standard 2.0): compare, plan, run, check afterwards, rollback, and the selection rules. It talks to an `IDataverse`, not to the SDK, and reads the same `config/manifest.json` as the PowerShell engine (embedded). |
| `xrmtoolbox/src/CcAlm.XrmToolBox` | The tool (.NET Framework 4.8, Windows Forms): the XrmToolBox plugin, its window, and `SdkDataverse`, the `IDataverse` over an XrmToolBox connection (`IOrganizationService`). |
| `xrmtoolbox/tests/CcAlm.Core.Tests` | The engine's tests against an in-memory Dataverse built from the same JSON as the PowerShell tests: the synthetic Dev and Test on Microsoft's schema, and every recording in `tests/fixtures/recorded`. |
| `xrmtoolbox/tests/CcAlm.LiveCheck` | Read-only: the C# engine over the SDK against two real environments, signed in with `az`. |
| `xrmtoolbox/icon.png`, `xrmtoolbox/package-readme.md` | The icon and the readme of the Tool Library listing. The icon is drawn by `scripts/make-icons.ps1`, which also writes `Icons.cs` (the tool list's 32 and 80 px) and the exe's `.ico`, so everything carries the same icon. |
| `xrmtoolbox/tests/CcAlm.UiCheck` | Opens the tool on the synthetic data against a real XrmToolBox install and saves a screenshot of each tab and of both review views; `--mef` checks that XrmToolBox finds it. Without an interactive desktop the window draws itself, so it also works over a terminal or on a build agent. |

The two engines are held to the same answers. The recorded tests require the C# engine to compare and plan a recording exactly as the PowerShell engine did when it was recorded (`baseline.json`), table by table. On a real Dev to Test the C# engine over the SDK and the PowerShell engine over the Web API gave the same 95 new, 38 changed, 53 only in the target, 43 the same and 2 ambiguous, and the same plan.

### Build

```powershell
./xrmtoolbox/build.ps1
```

Runs the engine tests, builds the tool in Release and writes `out/ContactCenterALM.XrmToolBox.<version>.nupkg` (the Tool Library package: the tool and the engine under `lib\net48\Plugins`, depending on `XrmToolBoxPackage`) and `out/ContactCenterALM-XrmToolBox.zip`. XrmToolBox provides the Dataverse SDK, the connection library and Newtonsoft.Json, so they are not in the package.

### Publish to the Tool Library

The Tool Library is nuget.org: XrmToolBox lists packages tagged `XrmToolBox` once its team has reviewed the first version. The package carries that tag, the tool's icon, its own readme, the MIT licence and the repository link, and the two DLLs under `lib\net48\Plugins\`, which is what XrmToolBox installs.

1. Sign in at [nuget.org](https://www.nuget.org) with a Microsoft account and create an API key: **your name > API Keys > Create**, scope *Push new packages and package versions*, glob pattern `ContactCenterALM.*`. Copy it; it is shown once.
2. Build and push:

   ```powershell
   ./xrmtoolbox/build.ps1
   dotnet nuget push ./out/ContactCenterALM.XrmToolBox.<version>.nupkg --source https://api.nuget.org/v3/index.json --api-key <key>
   ```

   A version number is final: nuget.org never accepts the same one twice (unlisting is the only way back), so check the package first with `unzip -l` or [NuGet Package Explorer](https://github.com/NuGetPackageExplorer/NuGetPackageExplorer).
3. Validation takes a few minutes, then the package is live on nuget.org. The first version also goes to the XrmToolBox team for review; when they approve it, the tool appears in the Tool Library inside XrmToolBox. Later versions are listed without a new review.

### Test

```powershell
dotnet test xrmtoolbox/tests/CcAlm.Core.Tests
dotnet run --project xrmtoolbox/tests/CcAlm.LiveCheck -- https://contoso-dev.crm4.dynamics.com https://contoso-test.crm4.dynamics.com
```
