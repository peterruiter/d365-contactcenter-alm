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
  "displayColumn": "msdyn_name",
  "notes": "..."
}
```

| Field | Purpose |
| --- | --- |
| `order` | Global write order. Parents before children. The engine sorts on this. |
| `stage` | Groups tables into pipeline stages. Stages run in order; a stage reports as a unit, and every canonical stage shows in the plan even when it has nothing to move. |
| `logicalName` / `entitySet` | Table logical name and its Web API entity set. |
| `move` | `upsert`, `create-once`, `selective`, or `detect`. See below. |
| `matchKeys` | Columns that form the natural key. The diff, and the write engine's create-vs-update decision, both match on this - never on a raw GUID or a Dataverse alternate key. If a matchKey column is itself a lookup (`_x_value`), the engine resolves it to *its own* natural key first, so the composite key stays comparable across environments even though the raw GUID never is. |
| `alternateKey` | Metadata only, not read by the engine. Kept as documentation of the table's natural identity for humans; earlier versions used it to build upsert URLs, but a registered Dataverse alternate key is org-specific metadata that is not guaranteed to exist even when the manifest names one, so the write engine now decides create vs. update purely from the `matchKeys` match found during compare. |
| `select` | Columns to read and diff. The first is the primary key. |
| `lookups` | Lookup columns to resolve to natural keys. `column` is the logical lookup, `target` the referenced table, `targetKey` its match column (informational only - the target table's own configured `matchKeys` is what the engine actually resolves against). |
| `async` | Set on tables whose create fires async provisioning. The write engine waits after each create. |
| `guidBearingColumns` | Columns holding embedded GUIDs, like `msdyn_rulesetdefinition`. The engine remaps them on write and normalises them on diff. Every GUID found in these columns is also tracked as a dependency, the same as a `lookups` entry - it shows as a "Requires" hint in the app and gets auto-selected alongside the record. A GUID that still cannot be resolved at write time (its referenced record has not landed in target) makes the engine skip that write with a warning instead of sending Dataverse a definition it will reject outright. |
| `doubleWrite` | Write the record twice. Rulesets need this to land dependency mappings. |
| `stripColumns` | Columns to drop on write entirely - values that are per-environment and should never be copied (phone numbers, bot references). |
| `skipColumns` | Columns to leave out of the diff *and* the write payload. Only use this for columns that genuinely should never be written - a column you still need Dataverse to receive (even a boolean that "shouldn't differ") does not belong here, or the write silently omits it and Dataverse defaults it, which can be worse than a diff false-positive. `msdyn_isomnichannelqueue` on `queue` was briefly here for exactly this reason: skipping it let every created queue default to `false`, which then made it invisible to the next compare's `personalFilterColumn` filter and caused runaway duplicate creates. |
| `personalFilterColumn` | A boolean column that separates "real" records from ones Dataverse auto-provisions (personal/system queues, one per user). Records where this column is `false` are always excluded from both source and target reads - no override. Must be in `select`, must *not* be in `skipColumns` (see above). |
| `displayColumn` | A column on the record to show as a friendly heading in the app, with the technical match key underneath in small text, instead of the raw match key as the only label. |
| `displayTemplate` | Like `displayColumn`, but a template string with `{fieldName}` tokens substituted from the record's own columns - for tables with no name field of their own, e.g. `"Step {msdyn_sequence}"` for routing/assignment steps. |
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
2. Pick match keys that are stable and unique. A name usually. Add parent columns if a name alone is not unique - Dataverse auto-provisions one "default" record per parent for several of these tables (a routing config per workstream, for instance), and they all share the same name, so the name alone silently collides.
3. List the columns to read in `select`, primary key first, and check for `SystemRequired` columns you might be missing (see below).
4. Declare every lookup you want resolved.
5. Set `order` so parents write first.
6. `alternateKey` is metadata only now (see the field table above) - set it if the table has one, for documentation, but it changes no engine behaviour.

Adding a lookup to an existing table:

1. Add the lookup value column to `select` as `_column_value`.
2. Add the lookup entry with `column`, `target`, `targetKey`.
3. Confirm the target table is in the manifest with a lower `order`.

## Things to confirm against your org

- **Entity set names.** Quick replies (`msdyn_cannedmessageses`) and tags (`msdyn_octagses`) have plural forms that vary. Verify with a `GET /api/data/v9.2/<entityset>?$top=1`.
- **System-required columns.** A column Dataverse marks `SystemRequired` and `IsValidForCreate` must be in `select` or every create fails with a "cannot be NULL" error, even if nothing in the app or the CMT export ever shows it. `msdyn_uniquename` on the routing/assignment config and step tables is the recurring example - check new tables against `GET /api/data/v9.2/EntityDefinitions(LogicalName='<table>')/Attributes?$select=LogicalName,RequiredLevel,IsValidForCreate&$filter=RequiredLevel/Value eq 'SystemRequired' and IsValidForCreate eq true` before assuming `select` is complete.
- **Ruleset JSON shape.** `guidBearingColumns` assumes the current `msdyn_rulesetdefinition` structure. If Microsoft changes it, the remap needs a look.
