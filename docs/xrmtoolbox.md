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
3. **Compare** reads both. The Review tab lists every difference, grouped as Foundations, Workstreams, Queues, Routing, Channels and Agent content, each record marked New, Changed, Ambiguous or Only in target (Same is hidden; tick it to see those too). Select a record to see what differs, what it needs and everything under it.
4. **Tick what to move.** Ticking a record also ticks everything under it and what that uses: a workstream brings its routing configuration, its work classification and route-to-queue steps, their rulesets, its queues, templates and the rest. Unticking takes them away again, except what another ticked record still needs. *Select all* above the tree works on what the filters and search show.
5. **Check the plan.** Every ticked record is checked before anything is written: each of its parents, templates and embedded references must be in the target, be created earlier in the same run, or be linked at the end. Anything that cannot is blocked, with the reason. **Add what is missing** adds the records a blocked one needs.
6. **Dry run.** Goes through every write without writing anything. It reuses what the compare read, so it is fast.
7. **Apply.** Unlocks after a dry run of the same plan. It reads the target again first, so it never writes from an old picture, snapshots every record it changes, and ends by reading back everything it wrote. The Run tab then says the target matches the source, or lists each record that still differs with the setting and both values, and why when Dataverse is the reason. Records Dataverse created on its own during the run (the routing contract of a new workstream) are listed too.
8. **Roll back.** *Roll back this run* undoes the last apply; *Roll back a run…* any earlier one from its snapshot. Changed records get their settings and lookups back, created ones are deleted, children first.

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
| `xrmtoolbox/tests/CcAlm.UiCheck` | Opens the tool on the synthetic data against a real XrmToolBox install and saves a screenshot of each tab; `--mef` checks that XrmToolBox finds it. |

The two engines are held to the same answers. The recorded tests require the C# engine to compare and plan a recording exactly as the PowerShell engine did when it was recorded (`baseline.json`), table by table. On a real Dev to Test the C# engine over the SDK and the PowerShell engine over the Web API gave the same 95 new, 38 changed, 53 only in the target, 43 the same and 2 ambiguous, and the same plan.

### Build

```powershell
./xrmtoolbox/build.ps1
```

Runs the engine tests, builds the tool in Release and writes `out/ContactCenterALM.XrmToolBox.<version>.nupkg` (the Tool Library package: the tool and the engine under `lib\net48\Plugins`, depending on `XrmToolBoxPackage`) and `out/ContactCenterALM-XrmToolBox.zip`. XrmToolBox provides the Dataverse SDK, the connection library and Newtonsoft.Json, so they are not in the package.

Publishing to the Tool Library is pushing that package to nuget.org; XrmToolBox lists packages tagged `XrmToolBox` after a review.

### Test

```powershell
dotnet test xrmtoolbox/tests/CcAlm.Core.Tests
dotnet run --project xrmtoolbox/tests/CcAlm.LiveCheck -- https://contoso-dev.crm4.dynamics.com https://contoso-test.crm4.dynamics.com
```
