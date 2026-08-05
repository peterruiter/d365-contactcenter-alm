# Usage

The app walks one flow: compare, pick, plan, run, roll back.

## 1. Pick source and target

Choose the environment to read from and the one to write to. They must differ. A target marked "(approval)" needs sign-off before you can apply.

## 2. Compare

Hit Compare. You get:

- **Four cards**: missing in target, changed, extra in target, equal.
- **Differences**, grouped by table. Each record shows a status and, for changed records, the field deltas (target value -> source value).
- **Provision in target**: the detect-only panel. Phone numbers, bots, channel accounts. The tool reports these and leaves them alone.

Toggle "Show equal" to see records that already match. They are hidden by default so you look at what differs.

## 3. Pick what moves

Tick records to move, or tick a whole table. Only missing and changed records are movable. Leave everything unticked to move all of them.

## 4. Build a plan

Build plan turns your selection into ordered operations, grouped by stage. Parents land before the records that point at them. Read the order before you run anything.

## 5. Run

Run opens a dialog with two choices:

- **Dry run**: reports what would happen, writes nothing. Do this first.
- **Apply**: writes to the target. A target that needs approval makes you tick the approval box first.

The run view shows each stage, how many records it wrote, and any warnings. Provisioning warnings show up here; they are the usual source of "it looked fine but wasn't".

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
