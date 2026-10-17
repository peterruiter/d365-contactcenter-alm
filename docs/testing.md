# Testing the engine

The engine's tests run offline: no environment, no network, nothing written anywhere. They run the real engine (compare, plan, dry run, apply, the check afterwards, rollback, background runs) against an in-memory Dataverse.

```powershell
Install-Module Pester -Scope CurrentUser -Force -SkipPublisherCheck   # once; Pester 5.5 or later
./scripts/test.ps1
./scripts/test.ps1 -Path tests/Scenario.Tests.ps1                      # one file
```

They also run on every push to `master` (`.github/workflows/tests.yml`).

## What is tested

| File | What it covers |
| --- | --- |
| `tests/Engine.Tests.ps1` | Small pure pieces: value comparison, GUID rewriting in definitions, error messages, stale runs, run records. |
| `tests/Scenario.Tests.ps1` | The whole engine on a synthetic Dev and Test (below): what compare finds, what the plan blocks and why, a dry run that writes nothing, an apply that ends with every written record the same as the source, rollback to exactly the state before, a run split over time-budgeted slices, and what the check afterwards reports when a write fails, when Dataverse changes a value afterwards, and when it provisions records on its own. |
| `tests/Recorded.Tests.ps1` | Every recording of real environments in `tests/fixtures/recorded`, replayed: compare and plan as they were recorded, nothing to move between an environment and itself, a dry run that writes nothing, an apply into a copy of the target that fails nothing and checks out, and a rollback that puts it back. Skipped when there are no recordings, as on a fresh clone. |

## The in-memory Dataverse

`tests/support/FakeDataverse.ps1` answers the Web API calls the engine makes: `EntityDefinitions`, reads with `$select` and `$filter`, create, update, delete, `@odata.bind` and `$ref`. It is as strict as Dataverse where that matters: a `$select` of a column the table does not have, writing a column that is not valid for create or update, or binding a navigation property the table does not have fails with the error Dataverse gives.

`Mount-CcFakeDataverse` imports a fresh copy of the module with `Invoke-CcWebApi` pointed at the fake orgs, and with a virtual clock: `Start-Sleep` moves the clock on instead of waiting, and `-LatencySeconds` makes every call take that much of it. A 90-second provisioning wait or a 7-minute slice passes in milliseconds, and the same way on every run.

A fake org can also:

- provision a routing configuration and step when a workstream is created (`-ProvisionRoutingConfiguration`), as Dataverse does for some workstreams;
- fail chosen writes (`FailWhen`), returning a message as Dataverse would;
- change a record after a write (`OnWrite`), like a plugin.

## The synthetic scenario

`tests/support/SyntheticScenario.ps1` builds a small Dev and Test on Microsoft's real Contact Center schema, `tests/fixtures/schema.json`. The table at the top of that file lists every record and what the engine should make of it. It covers matching across GUIDs, duplicate names with a tie-breaker, ambiguous records, rulesets with embedded GUIDs, links set in the final pass, a template from a managed solution, a channel that needs a per-environment account, create-once contracts, personal queues, and records with no dependencies.

`tests/fixtures/schema.json` is the metadata the engine reads, for the manifest's tables only, with no records. Refresh it when a Dynamics release changes those tables:

```powershell
./tests/support/Export-CcSchemaFixture.ps1 -From tests/fixtures/recorded/<name>/source.metadata.json
```

## Recording real environments

```powershell
az login
./scripts/record-fixture.ps1 -Name dev-test -SourceUrl https://contoso-dev.crm4.dynamics.com -TargetUrl https://contoso-test.crm4.dynamics.com -SourceName Dev -TargetName Test
```

This runs the engine's own compare against both environments with your Azure CLI sign-in (add `-Subscription` when the login that can read them is not your default). It only reads: the recorder refuses anything but a GET. It saves every metadata and record response to `tests/fixtures/recorded/<name>`, plus `baseline.json`, which holds what compare and plan found. The recorded tests then fail if a later engine change shifts those numbers. When that change is intended, record again.

**Recordings hold real configuration**: names, settings, GUIDs, message texts. `tests/fixtures/recorded/` is in `.gitignore`. Keep it there and never commit a recording, least of all from a client's environments.
