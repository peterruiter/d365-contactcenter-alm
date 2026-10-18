# Contact Center ALM

Move Dynamics 365 Contact Center configuration between environments, from inside
[XrmToolBox](https://www.xrmtoolbox.com): workstreams with their routing configurations, work
classification and route-to-queue rules, queues, rulesets, decision contracts, templates, capacity
profiles, channels and agent content. No Configuration Migration tool, no schema file, no hand-edited
`data.xml`, no GUID edits.

It runs on your own XrmToolBox connections — the tool's connection is the source, a second one the
target — so there is no backend to deploy and no app registration to create.

## What it does

1. **Compare** reads both environments and shows every difference, by structure: each record sits
   under the workstream, channel or queue it belongs to, and the things it uses — the ruleset a step
   runs, the queue it routes to — are shown where they are used.
2. **Tick what to move.** A record brings everything under it and what that uses.
3. **Check the plan.** Every dependency is checked before anything is written. Anything that cannot
   be written is blocked, with the reason, and the records that would unblock it.
4. **Dry run**, then **apply**. An apply reads the target again first, snapshots every record it
   changes, and ends by reading back everything it wrote to check the target now matches the source.
5. **Roll back** any run from its snapshot.

Records are matched on what they are — their names and their parents — never on their GUIDs, so two
identical workstreams in two environments are recognised as the same workstream.

## Before you use it

Writing Contact Center configuration through the API is not a Microsoft-supported path. Dry-run
first, and try it on Dev and Test before Production.

Full documentation:
[docs/xrmtoolbox.md](https://github.com/peterruiter/d365-contactcenter-alm/blob/master/docs/xrmtoolbox.md).
Source, issues and the Power Apps version of the same tool:
[github.com/peterruiter/d365-contactcenter-alm](https://github.com/peterruiter/d365-contactcenter-alm).

Built by Peter Ruiter. MIT licensed.
