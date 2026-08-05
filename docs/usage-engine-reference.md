# Usage

Compare, migrate, and roll back. Every write path is dry-run first.

## Setup once

```powershell
Import-Module ./src/CcAlm/CcAlm.psd1
Copy-Item ./config/environments.example.json ./environments.json
# edit tenantId, clientId, and the four environment URLs
$env:CCALM_CLIENT_SECRET = '<your secret>'
```

## Compare

```powershell
./scripts/compare.ps1 -Config ./environments.json -Source acc -Target prod
```

You get a console summary and two files in `./out`:

- `diff-acc-to-prod-<stamp>.md` — a readable diff, per table, with field deltas and the detect-only gaps
- `diff-acc-to-prod-<stamp>.json` — the same as data

Limit it to a few tables while you are testing:

```powershell
./scripts/compare.ps1 -Config ./environments.json -Source dev -Target test -Tables msdyn_liveworkstream,queue,msdyn_decisionruleset
```

Read the summary before you move anything. MissingInTarget and Changed are what a migrate will write. ExtraInTarget is config in the target that is not in the source; the tool never deletes it.

## Migrate: dry-run

Dry-run is the default. It builds the plan, reports every operation, and writes nothing.

```powershell
./scripts/migrate.ps1 -Config ./environments.json -Source acc -Target prod
```

Read the plan. It lists operations by stage and manifest order, so you can see parents landing before children. Check the "Problems flagged" section at the end. Unmapped ruleset GUIDs or missing parents show up here.

## Migrate: apply

```powershell
./scripts/migrate.ps1 -Config ./environments.json -Source acc -Target prod -Apply -Approved
```

- `-Apply` switches from dry-run to writing.
- `-Approved` is required for any environment with `requireApproval: true`. Prod, by default.

What happens:

1. A snapshot of the target rows the plan touches lands in `./out/snapshot-run_<id>.json`.
2. Stages run in order. Each reports a written count and any warnings.
3. Workstream creates wait for provisioning before the run moves on.
4. Rulesets write twice, to land dependency mappings.
5. A run record lands in `./out/run-run_<id>.json`.

If a write fails, the run stops at that stage, writes the run record with state `PartiallyFailed`, and tells you the snapshot path to roll back.

## Roll back

```powershell
./scripts/rollback.ps1 -Config ./environments.json -Snapshot ./out/snapshot-run_<id>.json
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
