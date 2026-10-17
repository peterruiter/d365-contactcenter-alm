# Manifest

`config/manifest.json` says **which** Contact Center tables move, in which order and stage, and how a record is recognised in another environment. It does **not** list columns or lookups: the engine reads those from each environment's own metadata (`EntityDefinitions`), so it compares and writes every writable setting the two orgs share, and follows the real lookups.

That is the main change from version 1, which listed columns by hand. Those lists drifted from Dataverse: lookups were renamed (`msdyn_rulesetid`, not `msdyn_decisionrulesetid`), settings were added every release, and most of a workstream's or queue's configuration was never compared or moved. Version 2 manifests are required; the engine refuses a version 1 file.

`backend/function-app/manifest.json` is a copy for the Azure Function. `scripts/deploy-backend.ps1` refreshes it; keep the two identical.

## A table entry

```json
{
  "order": 15, "stage": 7, "logicalName": "msdyn_routingconfigurationstep", "item": "routing step",
  "move": "upsert",
  "label": "Routing steps", "group": "Routing",
  "matchKeys": ["_msdyn_routingconfigurationid_value", "msdyn_name"],
  "notes": "Steps such as classification and route-to-queue, under their routing configuration."
}
```

| Field | Meaning |
| --- | --- |
| `order` | Write order. Parents before children. A lookup to a table with the same or a later `order` is **linked in a final pass** (stage "Link records written earlier") instead of set on the first write: a workstream's default queue, a queue's overflow ruleset. |
| `stage` | The group the plan and the run show the record under. Stage labels and descriptions are in the top-level `stages` list. |
| `logicalName` | The Dataverse table. The entity set name comes from metadata. |
| `label`, `item`, `group` | What people read: the plural label ("Routing steps"), the singular noun used in sentences ("routing step"), and the functional area the review screen groups by. |
| `move` | `upsert` (create or update), `create-once` (create when missing, never change), `update-only` (never create: one per environment, such as the Omnichannel configuration), `reference` (read so lookups to it can be mapped, never compared or written, such as languages), `detect` (report only). |
| `matchKeys` | How a record is recognised in the other environment, never by GUID. A matchKey that is a lookup (`_x_value`) is replaced by the parent's own key, **recursively**, so a routing step's key contains its configuration's key, which contains its workstream's key, and no environment-specific GUID survives at any depth. |
| `tieBreaker` | Optional column used only when two records in one environment share a key (two capacity profiles with the same name). Applied on both sides consistently. If that still collides, the records are reported as **Ambiguous** and never paired at random. |
| `exclude` | Columns never compared or written for this table: secrets, environment-generated values, per-environment links (`msdyn_apikey`, `msdyn_widgetsnippet`, `msdyn_inboundurl`, `msdyn_calendarid`). The top-level `systemColumns` and `excludeColumns` apply to every table. |
| `textReferences` | Text columns that name another record by unique name. A workstream's `msdyn_sessiontemplate_default` holds a session template's `msdyn_uniquename`. `columns` may end in `*`. These become dependencies: the template has to exist in the target. `label` is what the dependency is called in messages. |
| `guidBearingColumns` | Columns with GUIDs embedded in text, such as `msdyn_rulesetdefinition`. Compared by what the GUIDs point at (each side normalised with its own map), rewritten to the target's GUIDs on write, and every GUID becomes a dependency. |
| `displayTemplate` | How to name a record that has no good name of its own, e.g. `"{_msdyn_capacityprofile_id_value}"` uses the formatted value of a lookup. |
| `personalFilterColumn` | Boolean column separating real records from ones Dataverse provisions per user (personal queues). Only rows where it is `true` are read. |
| `async` | Creating it starts provisioning; the run waits for the side-effect records. |
| `doubleWrite` | Write twice so Dataverse records the dependencies (rulesets). |

## What the engine works out per table

For each pair of environments (`Resolve-CcTablePlan` in `Private/Get-CcSchema.ps1`):

- **Settings**: every attribute that is readable and creatable or updatable, not a lookup, not system, not excluded, and present in **both** orgs. One missing in the target (an older version) is listed as a notice on the compare and not copied.
- **Lookups**: every many-to-one relationship whose target is another manifest table. Lookups to tables this tool does not move (a bot user, a survey, a phone number record) are left alone.
- **Required per-environment records**: a required lookup to a table this tool does not move (an SMS channel's phone number) blocks **creating** that record in the plan, with the reason. Updating an existing one is fine.

## Preflight

Before anything runs, every planned record's dependencies (lookups, named templates, embedded GUIDs) are checked: already in the target, created earlier in this run, linked at the end, or missing. Missing ones are added automatically when "Add the records they need" is on, or shown as blockers with an "Add …" fix when it is off. A record that waits on a blocked record is blocked too. See `New-CcPlan`.

## Adding a table

1. Add the entry with an `order` after everything it points at, a `stage`, `label`, `item`, `group`, `move` and `matchKeys`.
2. Pick match keys that are stable across environments: a unique name the product generates the same everywhere, or a name plus the parent lookup. Avoid unique names Dataverse generates randomly per environment (`new_<guid>`).
3. List anything environment-specific under `exclude`.
4. Compare an environment with itself (`./backend/cli/compare.ps1 -Source dev -Target dev` with the same URL twice). Every record must come out **Same**. Anything else is a matching problem.
