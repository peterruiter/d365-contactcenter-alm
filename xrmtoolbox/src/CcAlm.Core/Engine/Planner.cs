using System;
using System.Collections.Generic;
using System.Linq;

namespace CcAlm.Core.Engine
{
    public sealed class Blocker
    {
        public string Code { get; set; }
        public string Message { get; set; }
        /// <summary>The record that would unblock it (code missingDependency), to add to the selection.</summary>
        public string FixRef { get; set; }
        public string FixLabel { get; set; }
    }

    public sealed class PlanDependency
    {
        public string Table { get; set; }
        public string MatchKey { get; set; }
        public string Label { get; set; }
        public string Via { get; set; }
        /// <summary>inTarget, createdEarlier, linkedLater or missing.</summary>
        public string State { get; set; }
        public string Ref => $"{Table}|{MatchKey}";
    }

    public sealed class PlanOperation
    {
        public int Seq { get; set; }
        public int Stage { get; set; }
        public int Order { get; set; }
        public string Table { get; set; }
        public string TableLabel { get; set; }
        /// <summary>create, update or skip-existing.</summary>
        public string Op { get; set; }
        public string MatchKey { get; set; }
        public string DisplayName { get; set; }
        public string Context { get; set; }
        public bool AutoIncluded { get; set; }
        public List<string> NeededBy { get; } = new List<string>();
        public List<string> Changes { get; } = new List<string>();
        /// <summary>ready or blocked.</summary>
        public string Status { get; set; } = "ready";
        public List<PlanDependency> Dependencies { get; } = new List<PlanDependency>();
        public List<Blocker> Blockers { get; } = new List<Blocker>();
        public List<string> Warnings { get; } = new List<string>();
        public string Ref => $"{Table}|{MatchKey}";
        public string FullName => string.IsNullOrEmpty(Context) ? DisplayName : $"{Context} › {DisplayName}";
    }

    public sealed class IgnoredSelection
    {
        public string Table { get; set; }
        public string MatchKey { get; set; }
        public string DisplayName { get; set; }
        public string Reason { get; set; }
    }

    public sealed class PlanSummary
    {
        public int Total { get; set; }
        public int Ready { get; set; }
        public int Blocked { get; set; }
        public int AutoIncluded { get; set; }
        public int Creates { get; set; }
        public int Updates { get; set; }
        public int Links { get; set; }
    }

    public sealed class Plan
    {
        public string PlanId { get; set; }
        public DiffModel Diff { get; set; }
        public List<PlanOperation> Operations { get; } = new List<PlanOperation>();
        public List<IgnoredSelection> Ignored { get; } = new List<IgnoredSelection>();
        public PlanSummary Summary { get; set; }
    }

    /// <summary>
    /// Turns a diff into ordered writes and checks, before anything runs, that every write can
    /// succeed: each record's parents, templates and embedded references must be in the target, be
    /// created earlier in the run, or be linked in the final pass. Anything that cannot is blocked,
    /// with the reason and, where there is one, the fix.
    /// </summary>
    public static class Planner
    {
        /// <param name="selection">"table|key" refs to move. null plans every new and changed record; an empty list plans nothing.</param>
        /// <param name="includeDependencies">Also plan the new records the selection needs.</param>
        public static Plan Build(DiffModel diff, IEnumerable<string> selection = null, bool includeDependencies = true)
        {
            var maps = diff.Maps;
            var plans = diff.TablePlans;
            var byRef = new Dictionary<string, RecordDiff>();
            foreach (var r in diff.AllRecords) byRef[r.Ref] = r;
            bool Movable(string reference) => byRef.TryGetValue(reference, out var e) && e.IsMovable;

            var planned = new Dictionary<string, string>();          // ref → why it is in the plan
            var plannedOrder = new List<string>();
            var neededBy = new Dictionary<string, List<string>>();
            var result = new Plan { PlanId = "pln_" + Guid.NewGuid().ToString("N").Substring(0, 12), Diff = diff };

            var start = selection != null ? selection.Where(s => !string.IsNullOrEmpty(s)).Distinct().ToList() : byRef.Keys.Where(Movable).ToList();
            foreach (var reference in start)
            {
                if (Movable(reference)) { if (!planned.ContainsKey(reference)) { planned[reference] = "selected"; plannedOrder.Add(reference); } }
                else if (byRef.TryGetValue(reference, out var r))
                {
                    string why;
                    switch (r.Status)
                    {
                        case RecordStatus.Equal: why = "it is already the same in the target"; break;
                        case RecordStatus.ExtraInTarget: why = "it only exists in the target"; break;
                        case RecordStatus.Ambiguous: why = r.Note; break;
                        default: why = $"its status is {r.Status}"; break;
                    }
                    result.Ignored.Add(new IgnoredSelection { Table = r.Table, MatchKey = r.MatchKey, DisplayName = r.DisplayName, Reason = "Not moved: " + why });
                }
            }

            if (includeDependencies)
            {
                var queue = new Queue<string>(plannedOrder);
                while (queue.Count > 0)
                {
                    var entry = byRef[queue.Dequeue()];
                    foreach (var d in entry.DependsOn)
                    {
                        if (!byRef.TryGetValue(d.Ref, out var dEntry) || dEntry.Status != RecordStatus.MissingInTarget) continue;
                        if (!neededBy.TryGetValue(d.Ref, out var who)) neededBy[d.Ref] = who = new List<string>();
                        var label = Keys.RefLabel(maps, entry.Table, entry.MatchKey, plans);
                        if (!who.Contains(label)) who.Add(label);
                        if (!planned.ContainsKey(d.Ref)) { planned[d.Ref] = "dependency"; plannedOrder.Add(d.Ref); queue.Enqueue(d.Ref); }
                    }
                }
            }

            var orderOf = diff.Manifest.Tables.ToDictionary(t => t.LogicalName, t => t.Order);
            var opByRef = new Dictionary<string, PlanOperation>();
            int seq = 0;
            foreach (var reference in plannedOrder.OrderBy(x => orderOf[byRef[x].Table]).ThenBy(x => byRef[x].DisplayName, StringComparer.Ordinal))
            {
                var r = byRef[reference];
                var t = plans[r.Table].Table;
                var op = r.Status == RecordStatus.MissingInTarget ? "create" : "update";
                if (t.Move == "create-once" && op == "update") op = "skip-existing";
                var o = new PlanOperation
                {
                    Seq = ++seq, Stage = t.Stage, Order = t.Order, Table = r.Table, TableLabel = t.DisplayLabel, Op = op,
                    MatchKey = r.MatchKey, DisplayName = r.DisplayName, Context = r.Context, AutoIncluded = planned[reference] == "dependency",
                };
                if (neededBy.TryGetValue(reference, out var nb)) o.NeededBy.AddRange(nb);
                o.Changes.AddRange(r.Fields.Select(f => f.Label));
                result.Operations.Add(o);
                opByRef[reference] = o;
            }

            // Preflight every operation.
            foreach (var o in result.Operations)
            {
                var tplan = plans[o.Table];
                var r = byRef[o.Ref];
                if (o.Op == "skip-existing")
                {
                    o.Warnings.Add("Already exists in the target. This table is only ever created, never changed, so it is left as it is.");
                    continue;
                }
                if (o.Op == "create" && tplan.Table.Move == "update-only")
                    o.Blockers.Add(new Blocker { Code = "updateOnly", Message = $"{o.TableLabel} exist once per environment and are never created by this tool. Create it in the target first, then compare again." });
                if (o.Op == "create")
                    foreach (var ext in tplan.RequiredExternal)
                        o.Blockers.Add(new Blocker { Code = "external", Message = $"Needs a {ext.Label.ToLowerInvariant()} to be created, and that is set up per environment. Set this channel up in the target, then compare again to copy its settings." });

                foreach (var d in r.DependsOn)
                {
                    var unresolved = d.MatchKey.StartsWith("unresolved:", StringComparison.Ordinal);
                    var label = unresolved ? $"a {plans[d.Table].Table.ItemLabel} that no longer exists in the source" : Keys.RefLabel(maps, d.Table, d.MatchKey, plans);
                    var dep = new PlanDependency { Table = d.Table, MatchKey = d.MatchKey, Label = label, Via = d.Via };

                    if (maps.TargetKeyToGuid.ContainsKey(d.Ref)) dep.State = "inTarget";
                    else if (opByRef.TryGetValue(d.Ref, out var parentOp) && parentOp.Op == "create") dep.State = d.Deferred ? "linkedLater" : "createdEarlier";
                    else if (unresolved)
                    {
                        dep.State = "missing";
                        var lk = tplan.Lookups.FirstOrDefault(l => l.Label == d.Via);
                        if (lk != null && lk.Required) o.Blockers.Add(new Blocker { Code = "danglingRequired", Message = $"Its {d.Via} points at a record that no longer exists in the source. Fix it in the source first." });
                        else o.Warnings.Add($"Its {d.Via} points at a record that no longer exists in the source; that link is left empty.");
                    }
                    else
                    {
                        dep.State = "missing";
                        byRef.TryGetValue(d.Ref, out var dEntry);
                        var srcRec = diff.Source.ByKeyOne(d.Table, d.MatchKey);
                        if (dEntry != null && dEntry.Status == RecordStatus.MissingInTarget)
                            o.Blockers.Add(new Blocker { Code = "missingDependency", Message = $"Needs {label}, which is not in the target and not selected.", FixRef = d.Ref, FixLabel = "Add " + label });
                        else if (srcRec != null && srcRec.IsManaged)
                            o.Blockers.Add(new Blocker { Code = "managedMissing", Message = $"Needs {label}, which comes with a managed solution that is not installed in the target. Install that solution there first." });
                        else if (d.Kind == "name")
                        {
                            var named = d.MatchKey.Contains("=") ? d.MatchKey.Substring(d.MatchKey.IndexOf('=') + 1) : d.MatchKey;
                            o.Blockers.Add(new Blocker { Code = "notFound", Message = $"Its {d.Via.ToLowerInvariant()} names '{named}' which exists in neither environment. Fix it in the source first." });
                        }
                        else
                            o.Blockers.Add(new Blocker { Code = "notFound", Message = $"Needs {label}, which cannot be found in the target." });
                    }
                    o.Dependencies.Add(dep);
                }
                if (o.Blockers.Count > 0) o.Status = "blocked";
            }

            // A record waiting on a blocked one is blocked too, until nothing changes.
            bool changed;
            do
            {
                changed = false;
                foreach (var o in result.Operations)
                {
                    if (o.Status == "blocked") continue;
                    foreach (var dep in o.Dependencies)
                    {
                        if (dep.State != "createdEarlier" && dep.State != "linkedLater") continue;
                        if (opByRef.TryGetValue(dep.Ref, out var parent) && parent.Status == "blocked")
                        {
                            o.Blockers.Add(new Blocker { Code = "waitsOnBlocked", Message = $"Waits on {dep.Label}, which is blocked." });
                            o.Status = "blocked";
                            changed = true;
                            break;
                        }
                    }
                }
            } while (changed);

            var ops = result.Operations;
            result.Summary = new PlanSummary
            {
                Total = ops.Count,
                Ready = ops.Count(o => o.Status == "ready"),
                Blocked = ops.Count(o => o.Status == "blocked"),
                AutoIncluded = ops.Count(o => o.AutoIncluded),
                Creates = ops.Count(o => o.Op == "create"),
                Updates = ops.Count(o => o.Op == "update"),
                Links = ops.SelectMany(o => o.Dependencies).Count(d => d.State == "linkedLater"),
            };
            return result;
        }
    }
}
