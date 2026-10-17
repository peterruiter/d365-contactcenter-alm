# Usage

Compare, migrate, and roll back. Every write path is dry-run first.

## Setup once

```powershell
Import-Module ./backend/function-app/Modules/CcAlm/CcAlm.psd1
Copy-Item ./config/environments.example.json ./environments.json
# edit tenantId, clientId, and the four environment URLs
$env:CCALM_CLIENT_SECRET = '<your secret>'
```

## Compare

```powershell
./backend/cli/compare.ps1 -Config ./environments.json -Source acc -Target prod
```

You get a console summary and two files in `./out`:

- `diff-acc-to-prod-<stamp>.md` — a readable diff, per table, with field deltas and the detect-only gaps
- `diff-acc-to-prod-<stamp>.json` — the same as data

Limit it to a few tables while you are testing:

```powershell
./backend/cli/compare.ps1 -Config ./environments.json -Source dev -Target test -Tables msdyn_liveworkstream,queue,msdyn_decisionruleset
```

Read the summary before you move anything. MissingInTarget and Changed are what a migrate will write. ExtraInTarget is config in the target that is not in the source; the tool never deletes it.

## Migrate: dry-run

Dry-run is the default. It builds the plan, reports every operation, and writes nothing.

```powershell
./backend/cli/migrate.ps1 -Config ./environments.json -Source acc -Target prod
```

Read the plan. It lists operations by stage and manifest order, so you can see parents landing before children. `New-CcPlan` adds the new records a selection needs (`-IncludeDependencies $false` to turn that off) and prints every blocked record with the reason, such as a dependency that is not selected or a channel that needs a per-environment phone number.

## Migrate: apply

```powershell
./backend/cli/migrate.ps1 -Config ./environments.json -Source acc -Target prod -Apply -Approved
```

- `-Apply` switches from dry-run to writing.
- `-Approved` is required for any environment with `requireApproval: true`. Prod, by default.

What happens:

1. A snapshot of the target rows the plan touches lands in `./out/snapshot-run_<id>.json`.
2. Stages run in order. Each reports a written count and any warnings.
3. Workstream creates wait for provisioning before the run moves on.
4. Rulesets write twice, to land dependency mappings.
5. A GUID a record just landed at in target - a queue created in stage 4, say - is immediately usable by anything that references it in a later stage. A ruleset in stage 6 pointing at a queue created earlier in the *same* run resolves it correctly; nothing needs a second apply.
6. A record whose dependency genuinely is not in target (not selected this run) is skipped with a warning instead of attempted - the run continues to the rest of the plan rather than stopping there.
7. A run record lands in `./out/run-run_<id>.json`.

`PartiallyFailed` means some records did not move: blocked in the plan, skipped because a record they need failed, or failed themselves. Everything else in the run completed. Each problem names the record and the reason.

## Roll back

```powershell
./backend/cli/rollback.ps1 -Config ./environments.json -Snapshot ./out/snapshot-run_<id>.json
```

Rollback restores changed records to their pre-run state, in reverse order. It reports records the run created rather than deleting them, and it flags anything it could not restore. Read that output. A half-provisioned workstream needs a manual look, because async side-effects do not reverse cleanly.

## A safe first run

1. Compare Dev to Test on a few tables. Read the diff.
2. Dry-run the migrate. Read the plan and the problems.
3. Apply to Test. Check the result in the app.
4. Only then point it at Acc and Prod.

## Reading the diff status

| Status | Meaning | Migrate action |
| --- | --- | --- |
| MissingInTarget | In source, not in target | Create |
| Changed | In both, fields differ | Update (create-once tables: skip) |
| ExtraInTarget | In target, not in source | None. Never deleted. |
| Equal | Same after normalisation | None |

## Programmatic use

The scripts are wrappers. You can call the cmdlets directly for finer control, for example to move a selected subset:

```powershell
$envs = Connect-CcEnvironment -ConfigPath ./environments.json
$diff = Compare-CcConfig -Environments $envs -SourceId acc -TargetId prod -OutputDir ./out
$selection = @(
    @{ table = 'msdyn_liveworkstream'; matchKey = 'msdyn_name=sales chat|msdyn_mode=192350000|msdyn_streamsource=192350000' }
)
$plan = New-CcPlan -Diff $diff -Selection $selection
Invoke-CcPlan -Plan $plan -Environments $envs -Mode Apply -Approved -OutputDir ./out
```

The `matchKey` values come straight from the diff JSON.
