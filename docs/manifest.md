# The manifest

`config/manifest.json` is the spine. The engine and the docs read from it. Change what moves, in what order, by editing this file, not the code.

## Shape

```json
{
  "version": "1.0.0",
  "systemColumns": [ "createdon", "modifiedon", "ownerid", "..." ],
  "tables": [ { "..." } ],
  "detectOnly": [ { "..." } ]
}
```

## A table entry

```json
{
  "order": 8,
  "stage": 2,
  "logicalName": "msdyn_liveworkstream",
  "entitySet": "msdyn_liveworkstreams",
  "move": "upsert",
  "matchKeys": ["msdyn_name", "msdyn_mode", "msdyn_streamsource"],
  "alternateKey": null,
  "select": ["msdyn_liveworkstreamid", "msdyn_name", "..."],
  "lookups": [
    { "column": "msdyn_operatinghourid", "target": "msdyn_operatinghour", "targetKey": "msdyn_name" }
  ],
  "async": true,
  "guidBearingColumns": [],
  "doubleWrite": false,
  "stripColumns": [],
  "notes": "..."
}
```

| Field | Purpose |
| --- | --- |
| `order` | Global write order. Parents before children. The engine sorts on this. |
| `stage` | Groups tables into pipeline stages. Stages run in order; a stage reports as a unit. |
| `logicalName` / `entitySet` | Table logical name and its Web API entity set. |
| `move` | `upsert`, `create-once`, `selective`, or `detect`. See below. |
| `matchKeys` | Columns that form the natural key. The diff matches on these, not on GUID. |
| `alternateKey` | A registered Dataverse alternate key column, if one exists. Enables upsert by key. |
| `select` | Columns to read and diff. The first is the primary key. |
| `lookups` | Lookup columns to resolve to natural keys. `column` is the logical lookup, `target` the referenced table, `targetKey` its match column. |
| `async` | Set on tables whose create fires async provisioning. The write engine waits after each create. |
| `guidBearingColumns` | Columns holding embedded GUIDs, like `msdyn_rulesetdefinition`. The engine remaps them on write and normalises them on diff. |
| `doubleWrite` | Write the record twice. Rulesets need this to land dependency mappings. |
| `stripColumns` | Columns to drop on write. Phone numbers, bot references. |
| `skipColumns` | Columns to ignore on diff. |
| `notes` | Human note. Read these; they hold the gotchas. |

## Move modes

| Mode | Behaviour |
| --- | --- |
| `upsert` | Create if missing, update if changed. The default. |
| `create-once` | Insert only if missing. Never overwrite. Decision contracts use this, so an existing contract is left alone. |
| `selective` | Diff and report, move only fields the operator selects. The omnichannel configuration singleton uses this. |
| `detect` | Read and report, never write. |

## Detect-only rules

```json
{
  "logicalName": "msdyn_ocvoicechannelsetting",
  "signal": "msdyn_phonenumber",
  "type": "phoneNumber",
  "message": "Voice channel in source has an ACS phone number the target lacks. Re-acquire in the target."
}
```

If `signal` (a column, or a `_signal_value` lookup) has a value on a source record, the engine reports the gap with `message`. This is how the tool flags phone numbers, bots, and channel accounts without trying to move them.

## Extending it

Adding a table:

1. Find its logical name and entity set. Check the entity set name against your org; some plural forms are not what you would guess.
2. Pick match keys that are stable and unique. A name usually. Add parent columns if a name alone is not unique.
3. List the columns to read in `select`, primary key first.
4. Declare every lookup you want resolved.
5. Set `order` so parents write first.
6. If it has a real alternate key, set `alternateKey` to get idempotent upserts.

Adding a lookup to an existing table:

1. Add the lookup value column to `select` as `_column_value`.
2. Add the lookup entry with `column`, `target`, `targetKey`.
3. Confirm the target table is in the manifest with a lower `order`.

## Things to confirm against your org

- **Entity set names.** Quick replies (`msdyn_cannedmessageses`) and tags (`msdyn_octagses`) have plural forms that vary. Verify with a `GET /api/data/v9.2/<entityset>?$top=1`.
- **Alternate keys.** The manifest assumes some tables have a name alternate key. Register it, or leave `alternateKey` null and the engine falls back to GUID resolution.
- **Ruleset JSON shape.** `guidBearingColumns` assumes the current `msdyn_rulesetdefinition` structure. If Microsoft changes it, the remap needs a look.
