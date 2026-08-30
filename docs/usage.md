# Usage

The app walks one flow: compare, pick, plan, run, roll back.

> Running from a pipeline or the command line instead of the app? See [usage-engine-reference.md](usage-engine-reference.md) for the CLI scripts and the cmdlets directly.

## 1. Pick source and target

Choose the environment to read from and the one to write to. They must differ. A target marked "(approval)" needs sign-off before you can apply.

## 2. Compare

Hit Compare. You get:

- **Four cards**: missing in target, changed, extra in target, equal.
- **Differences**, grouped by table. Each record shows a status and, for changed records, the field deltas (target value -> source value). Where a friendly name exists (a workstream, a ruleset, a routing config), it shows as the heading with the technical match key underneath in small text, rather than the match key being the only label.
- A record that points at something else the tool tracks - a ruleset referencing a queue, a step referencing its parent config - shows a "Requires" hint naming what it needs. This is not only explicit lookup columns; a ruleset's embedded queue references count too.
- **Provision in target**: the detect-only panel. Phone numbers, bots, channel accounts. The tool reports these and leaves them alone.

Toggle "Show equal" to see records that already match. They are hidden by default so you look at what differs. Personal/system queues (one auto-provisioned per user, named after them) never show up here at all - they are never something to migrate.

## 3. Pick what moves

Tick records to move, or tick a whole table. Ticking a record also ticks anything it requires that has not landed in target yet, so a ruleset drags its referenced queues along and a step drags its parent config - you do not have to hunt down dependencies by hand. Only missing and changed records are movable. Leave everything unticked to move all of them.

## 4. Build a plan

Build plan turns your selection into ordered operations, grouped by stage. Parents land before the records that point at them. Read the order before you run anything.

## 5. Run

Run opens a dialog with two choices:

- **Dry run**: reports what would happen, writes nothing. Do this first.
- **Apply**: writes to the target. A target that needs approval makes you tick the approval box first.

The run view shows each stage, how many records it wrote, and any warnings. Provisioning warnings show up here; they are the usual source of "it looked fine but wasn't". A record whose dependency was not part of this run (not selected, or genuinely not in target yet) shows as skipped with a reason instead of being written broken - the rest of the run still completes. When that happens the overall status reads "Partially failed" even though nothing actually errored; it is telling you some records are waiting on something else to move first. The dependency auto-select in step 3 is what usually prevents this in the first place.

## 6. Roll back

After an apply, Roll back this run restores the target from the snapshot the run took. It puts changed records back and reports records the run created. A half-provisioned workstream needs a manual look, because async side-effects do not reverse cleanly.

## Reading the status

| Status | Meaning | On apply |
| --- | --- | --- |
| Missing in target | In source, not in target | Created |
| Changed | In both, fields differ | Updated (create-once tables skip) |
| Extra in target | In target, not in source | Left alone. Never deleted. |
| Equal | Same after normalisation | Left alone |

## A safe first run

1. Compare Dev to Test. Read the diff.
2. Build a plan. Read the order.
3. Dry run. Read the warnings.
4. Apply to Test. Check it in the app.
5. Only then point at Acc and Prod.
