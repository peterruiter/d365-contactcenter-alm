using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using CcAlm.Core.Model;

namespace CcAlm.Core.Engine
{
    public static class Outcome
    {
        public const string Created = "created", Updated = "updated", Linked = "linked", Unchanged = "unchanged";
        public const string WouldCreate = "wouldCreate", WouldUpdate = "wouldUpdate", WouldLink = "wouldLink";
        public const string Skipped = "skipped", Blocked = "blocked", Failed = "failed";
        public static readonly string[] Ok = { Created, Updated, Linked, Unchanged, WouldCreate, WouldUpdate, WouldLink };
        public static bool IsOk(string o) => Ok.Contains(o);
        public static bool IsWrite(string o) => o == Created || o == Updated || o == Linked;
    }

    public sealed class RunItem
    {
        public int Seq { get; set; }
        public int Stage { get; set; }
        public string Table { get; set; }
        public string MatchKey { get; set; }
        public string TableLabel { get; set; }
        public string DisplayName { get; set; }
        public string Context { get; set; }
        /// <summary>create, update, skip-existing or link.</summary>
        public string Op { get; set; }
        public string Outcome { get; set; }
        public string Message { get; set; }
        public string Ref => $"{Table}|{MatchKey}";
        public string FullName => string.IsNullOrEmpty(Context) ? DisplayName : $"{Context} › {DisplayName}";
    }

    /// <summary>The state of one target record before a run changed it, in a form rollback writes straight back.</summary>
    public sealed class SnapshotEntry
    {
        public string Table { get; set; }
        public Guid Id { get; set; }
        public string Label { get; set; }
        public int Order { get; set; }
        public Dictionary<string, object> Data { get; set; } = new Dictionary<string, object>();
        /// <summary>Lookup column → the record it pointed at, or null for empty.</summary>
        public Dictionary<string, SnapshotLookup> Lookups { get; set; } = new Dictionary<string, SnapshotLookup>();
    }

    public sealed class SnapshotLookup
    {
        public string Table { get; set; }
        public Guid Id { get; set; }
    }

    /// <summary>A many-to-many link a run made, for rollback to remove.</summary>
    public sealed class SnapshotLink
    {
        public ManyToManyInfo Relationship { get; set; }
        public Guid Id1 { get; set; }
        public Guid Id2 { get; set; }
        public string Label { get; set; }
    }

    public sealed class Snapshot
    {
        public string RunId { get; set; }
        public string Environment { get; set; }
        public DateTime Taken { get; set; }
        public List<SnapshotEntry> Updated { get; set; } = new List<SnapshotEntry>();
        public List<SnapshotEntry> Created { get; set; } = new List<SnapshotEntry>();
        public List<SnapshotLink> Linked { get; set; } = new List<SnapshotLink>();
    }

    public sealed class RunSummary
    {
        public int Created { get; set; }
        public int Updated { get; set; }
        public int Linked { get; set; }
        public int Skipped { get; set; }
        public int Blocked { get; set; }
        public int Failed { get; set; }

        public static RunSummary Of(IEnumerable<RunItem> items)
        {
            var list = items.ToList();
            int C(params string[] o) => list.Count(i => o.Contains(i.Outcome));
            return new RunSummary
            {
                Created = C(Outcome.Created, Outcome.WouldCreate), Updated = C(Outcome.Updated, Outcome.WouldUpdate), Linked = C(Outcome.Linked, Outcome.WouldLink),
                Skipped = C(Outcome.Skipped), Blocked = C(Outcome.Blocked), Failed = C(Outcome.Failed),
            };
        }
    }

    public sealed class RunResult
    {
        public string RunId { get; set; }
        /// <summary>dryRun or apply.</summary>
        public string Mode { get; set; }
        public string Source { get; set; }
        public string Target { get; set; }
        /// <summary>Succeeded, PartiallyFailed, Failed or Cancelled.</summary>
        public string State { get; set; }
        public DateTime StartedAt { get; set; }
        public DateTime? FinishedAt { get; set; }
        public List<RunItem> Items { get; set; } = new List<RunItem>();
        public RunSummary Summary { get; set; } = new RunSummary();
        public Snapshot Snapshot { get; set; }
        public Verification Verification { get; set; }
        public string Message { get; set; }
        public bool IsDryRun => Mode == "dryRun";
    }

    /// <summary>What a run reports while it goes.</summary>
    public sealed class RunProgress
    {
        public string Phase { get; set; }
        public int Done { get; set; }
        public int Total { get; set; }
        public string Current { get; set; }
        public RunItem Item { get; set; }
    }

    public sealed class RunOptions
    {
        public bool DryRun { get; set; } = true;
        public int ProvisioningTimeoutSeconds { get; set; } = 60;
        public CancellationToken Cancel { get; set; }
        public IProgress<RunProgress> Progress { get; set; }
        /// <summary>Called with the snapshot every time it grows, so a crash mid-run can still be rolled back.</summary>
        public Action<Snapshot> SaveSnapshot { get; set; }
        /// <summary>Waits without blocking a test run (the tests pass a no-op).</summary>
        public Action<TimeSpan> Sleep { get; set; } = t => Thread.Sleep(t);
        public Func<DateTime> Now { get; set; } = () => DateTime.UtcNow;
    }

    /// <summary>
    /// Runs a plan against the target. A dry run goes through every write exactly as apply would -
    /// payloads, reference rewriting, dependency order, the final link pass - and writes nothing; a
    /// record created earlier in the run gets a stand-in ID so the records that need it are checked
    /// against it. Apply snapshots what it changes and records what it creates.
    /// </summary>
    public static class Runner
    {
        sealed class PendingLink
        {
            public PlanOperation Op; public Guid RecordId; public PlanLookup Lookup; public string Entity; public string Key;
        }

        public static RunResult Run(Plan plan, IDataverse target, RunOptions options)
        {
            var diff = plan.Diff;
            var plans = diff.TablePlans;
            var maps = diff.Maps.CloneForRun();
            var dry = options.DryRun;
            var result = new RunResult
            {
                RunId = "run_" + Guid.NewGuid().ToString("N").Substring(0, 12),
                Mode = dry ? "dryRun" : "apply", Source = diff.SourceName, Target = diff.TargetName, StartedAt = options.Now(),
            };
            var items = result.Items;
            var ready = plan.Operations.Where(o => o.Status == "ready").OrderBy(o => o.Stage).ThenBy(o => o.Order).ThenBy(o => o.Seq).ToList();
            int total = ready.Count + plan.Summary.Links, done = 0;

            Snapshot snapshot = null;
            if (!dry)
            {
                snapshot = new Snapshot { RunId = result.RunId, Environment = target.Url, Taken = options.Now() };
                foreach (var o in ready.Where(x => x.Op == "update"))
                {
                    if (!maps.TargetKeyToGuid.TryGetValue(o.Ref, out var tid)) continue;
                    if (diff.Target.Table(o.Table).TryGetValue(tid, out var trec)) snapshot.Updated.Add(SnapshotOf(trec, plans[o.Table], tid, o));
                }
                options.SaveSnapshot?.Invoke(snapshot);
                result.Snapshot = snapshot;
            }

            void Report(string phase, string current, RunItem item = null) =>
                options.Progress?.Report(new RunProgress { Phase = phase, Done = done, Total = total, Current = current, Item = item });
            RunItem Add(PlanOperation o, string outcome, string message, int stage, string op = null)
            {
                var item = new RunItem
                {
                    Seq = o.Seq, Stage = stage, Table = o.Table, MatchKey = o.MatchKey, TableLabel = o.TableLabel,
                    DisplayName = o.DisplayName, Context = o.Context, Op = op ?? o.Op, Outcome = outcome, Message = message,
                };
                items.Add(item);
                Report(null, null, item);
                return item;
            }

            var failed = new HashSet<string>();
            foreach (var o in plan.Operations.Where(x => x.Status == "blocked"))
            {
                Add(o, Outcome.Blocked, string.Join(" ", o.Blockers.Select(b => b.Message)), o.Stage);
                failed.Add(o.Ref);
            }

            var links = new List<PendingLink>();
            foreach (var o in ready)
            {
                if (options.Cancel.IsCancellationRequested) { result.State = "Cancelled"; break; }
                Report("writing", $"{o.TableLabel}: {o.FullName}");
                var tplan = plans[o.Table];
                done++;

                if (o.Op == "skip-existing") { Add(o, Outcome.Unchanged, "Already in the target; this table is never changed after it is created.", o.Stage); continue; }

                if (tplan.Association != null)
                {
                    // A many-to-many link: both ends must be in the target or created earlier in this run.
                    var rel = tplan.Association.Relationship;
                    var waits = o.Dependencies.FirstOrDefault(d => (d.State == "createdEarlier" || d.State == "linkedLater") && failed.Contains(d.Ref));
                    if (waits != null) { Add(o, Outcome.Skipped, $"Not linked because {waits.Label} could not be written.", o.Stage); continue; }
                    var what = $"{o.Context} and {o.DisplayName}";
                    Guid end(string table) { var d = o.Dependencies.FirstOrDefault(x => x.Table == table); return d != null && maps.TargetKeyToGuid.TryGetValue(d.Ref, out var g) ? g : Guid.Empty; }
                    var id1 = end(rel.Entity1); var id2 = end(rel.Entity2);
                    if (id1 == Guid.Empty || id2 == Guid.Empty) { Add(o, Outcome.Skipped, $"Not linked: {what} are not both in the target.", o.Stage); continue; }
                    if (dry) { Add(o, Outcome.WouldLink, $"Will link {what}.", o.Stage); continue; }
                    try
                    {
                        target.Associate(rel, id1, id2);
                        snapshot.Linked.Add(new SnapshotLink { Relationship = rel, Id1 = id1, Id2 = id2, Label = what });
                        options.SaveSnapshot?.Invoke(snapshot);
                        Add(o, Outcome.Linked, $"Linked {what}.", o.Stage);
                    }
                    catch (Exception ex) { Add(o, Outcome.Failed, $"Could not link {what}: {ex.Message}", o.Stage); }
                    continue;
                }

                var waitsOn = o.Dependencies.FirstOrDefault(d => (d.State == "createdEarlier" || d.State == "linkedLater") && failed.Contains(d.Ref));
                if (waitsOn != null) { Add(o, Outcome.Skipped, $"Not written because {waitsOn.Label} could not be written.", o.Stage); failed.Add(o.Ref); continue; }

                var src = diff.Source.ByKeyOne(o.Table, o.MatchKey);
                if (src == null) { Add(o, Outcome.Failed, "The source record could not be found any more. Compare again.", o.Stage); failed.Add(o.Ref); continue; }

                var writeOp = o.Op == "create" ? "create" : "update";
                var built = BuildPayload(src, tplan, writeOp, maps, plans);
                if (built.Blocked) { Add(o, Outcome.Skipped, string.Join(" ", built.Problems), o.Stage); failed.Add(o.Ref); continue; }
                maps.TargetKeyToGuid.TryGetValue(o.Ref, out var existing);
                var targetId = o.Op == "update" ? existing : Guid.Empty;

                if (dry)
                {
                    var id = targetId != Guid.Empty ? targetId : Guid.NewGuid();
                    maps.TargetKeyToGuid[o.Ref] = id;
                    var n = built.Values.Count;
                    var deferred = built.Deferred.Count;
                    Add(o, o.Op == "create" ? Outcome.WouldCreate : Outcome.WouldUpdate,
                        $"{n} setting{(n != 1 ? "s" : "")} {(o.Op == "create" ? "set" : "written")}{(deferred > 0 ? $"; {deferred} link{(deferred != 1 ? "s" : "")} set at the end" : "")}.", o.Stage);
                    foreach (var d in built.Deferred) links.Add(new PendingLink { Op = o, RecordId = id, Lookup = d.Lookup, Entity = d.Entity, Key = d.Key });
                    continue;
                }

                try
                {
                    Guid id;
                    if (targetId != Guid.Empty) { target.Update(tplan.TargetSchema, targetId, built.Values); id = targetId; }
                    else
                    {
                        id = target.Create(tplan.TargetSchema, built.Values);
                        if (id == Guid.Empty) throw new DataverseException("Dataverse did not return the new record.");
                        snapshot.Created.Add(new SnapshotEntry { Table = o.Table, Id = id, Label = o.FullName, Order = o.Order });
                        options.SaveSnapshot?.Invoke(snapshot);
                    }
                    maps.TargetKeyToGuid[o.Ref] = id;

                    var note = "";
                    if (tplan.Table.Async && o.Op == "create")
                    {
                        var provisioned = WaitForProvisioning(target, tplan.TargetSchema, id, options);
                        if (provisioned == null) note = " Provisioning was not confirmed in time; check the workstream in the target.";
                        else if (provisioned.Id != Guid.Empty)
                        {
                            // Rollback deletes it too, after the workstream that points at it.
                            snapshot.Created.Add(new SnapshotEntry { Table = provisioned.Table ?? "msdyn_decisioncontract", Id = provisioned.Id, Label = $"Routing contract Dataverse created for {o.FullName}", Order = o.Order - 1 });
                            options.SaveSnapshot?.Invoke(snapshot);
                        }
                    }
                    if (tplan.Table.DoubleWrite)
                    {
                        // The second write lands the ruleset's dependency mappings, against its real id. It
                        // is an update, so it carries only what an update may set (not the unique name).
                        options.Sleep(TimeSpan.FromSeconds(2));
                        var second = writeOp == "create" ? BuildPayload(src, tplan, "update", maps, plans).Values : built.Values;
                        target.Update(tplan.TargetSchema, id, second);
                    }
                    Add(o, o.Op == "create" ? Outcome.Created : Outcome.Updated, ("Done." + note).Trim(), o.Stage);
                    foreach (var d in built.Deferred) links.Add(new PendingLink { Op = o, RecordId = id, Lookup = d.Lookup, Entity = d.Entity, Key = d.Key });
                }
                catch (Exception ex)
                {
                    Add(o, Outcome.Failed, ex.Message, o.Stage);
                    failed.Add(o.Ref);
                }
            }

            // Final pass: lookups that pointed at a table written later now have their target.
            if (result.State != "Cancelled")
            {
                foreach (var l in links)
                {
                    if (options.Cancel.IsCancellationRequested) { result.State = "Cancelled"; break; }
                    done++;
                    Report("linking", $"Linking {l.Op.FullName}");
                    var what = $"{l.Lookup.Label} of {plans[l.Op.Table].Table.ItemLabel} '{l.Op.DisplayName}'";
                    var refLabel = Keys.RefLabel(maps, l.Entity, l.Key, plans);
                    if (!maps.TargetKeyToGuid.TryGetValue($"{l.Entity}|{l.Key}", out var tg)) { Add(l.Op, Outcome.Skipped, $"{what} not set: {refLabel} is not in the target.", 99, "link"); continue; }
                    if (dry) { Add(l.Op, Outcome.WouldLink, $"{what} will point at {refLabel}.", 99, "link"); continue; }
                    try
                    {
                        target.Update(plans[l.Op.Table].TargetSchema, l.RecordId, new Dictionary<string, object> { [l.Lookup.Column] = new LookupValue(l.Entity, tg) });
                        Add(l.Op, Outcome.Linked, $"{what} now points at {refLabel}.", 99, "link");
                    }
                    catch (Exception ex) { Add(l.Op, Outcome.Failed, $"{what} could not be set: {ex.Message}", 99, "link"); }
                }
            }

            result.Summary = RunSummary.Of(items);
            if (result.State == null)
            {
                var bad = items.Count(i => !Outcome.IsOk(i.Outcome));
                var good = items.Count(i => Outcome.IsOk(i.Outcome) && i.Outcome != Outcome.Unchanged);
                result.State = bad == 0 ? "Succeeded" : good == 0 ? "Failed" : "PartiallyFailed";
            }
            result.FinishedAt = options.Now();
            return result;
        }

        sealed class Payload
        {
            public Dictionary<string, object> Values = new Dictionary<string, object>(StringComparer.OrdinalIgnoreCase);
            public List<(PlanLookup Lookup, string Entity, string Key)> Deferred = new List<(PlanLookup, string, string)>();
            public List<string> Problems = new List<string>();
            public bool Blocked;
        }

        /// <summary>
        /// The body for one source record aimed at the target: its data columns (those valid for this
        /// kind of write), each lookup bound to the target record it points at, GUIDs in definitions
        /// rewritten, and the lookups that wait for the link pass.
        /// </summary>
        static Payload BuildPayload(Record src, TablePlan tplan, string op, Maps maps, IDictionary<string, TablePlan> plans)
        {
            var p = new Payload();
            var attrs = tplan.TargetSchema.Attributes;
            foreach (var col in tplan.DataColumns)
            {
                if (!attrs.TryGetValue(col, out var a)) continue;
                if (op == "create" && !a.Create) continue;
                if (op == "update" && !a.Update) continue;
                var val = src.Get(col);
                if ((tplan.Table.GuidBearingColumns ?? new List<string>()).Contains(col) && val is string def && def.Length > 0)
                {
                    var rw = References.ToTarget(def, maps.SourceGuidToRef, maps.TargetKeyToGuid);
                    if (rw.Unmapped.Count > 0)
                    {
                        var names = rw.Unmapped.Select(u => Keys.RefLabel(maps, u.Entity, u.Key, plans)).Distinct();
                        p.Problems.Add($"Its {a.Label.ToLowerInvariant()} refers to {string.Join(", ", names)}, not in the target.");
                        p.Blocked = true;
                    }
                    val = rw.Text;
                }
                // On create an empty value is left out; on update it clears the setting.
                if (val == null && op == "create") continue;
                p.Values[col] = val;
            }

            foreach (var lk in tplan.Lookups)
            {
                if (!attrs.TryGetValue(lk.Column, out var a) || !lk.Writable) continue;
                if (op == "create" && !a.Create) continue;
                if (op == "update" && !a.Update) continue;
                var lv = src.GetLookup(lk.Column);
                if (lv == null) continue;
                if (!maps.SourceGuidToRef.TryGetValue(lv.Id.ToString(), out var rf))
                {
                    if (lk.Required) { p.Problems.Add($"Its {lk.Label.ToLowerInvariant()} points at a record that no longer exists in the source."); p.Blocked = true; }
                    continue;
                }
                if (lk.Deferred) { p.Deferred.Add((lk, rf.Entity, rf.Key)); continue; }
                if (!maps.TargetKeyToGuid.TryGetValue(rf.Ref, out var tg))
                {
                    p.Problems.Add($"Its {lk.Label.ToLowerInvariant()} is {Keys.RefLabel(maps, rf.Entity, rf.Key, plans)}, which is not in the target.");
                    p.Blocked = true;
                    continue;
                }
                p.Values[lk.Column] = new LookupValue(rf.Entity, tg);
            }
            return p;
        }

        /// <summary>
        /// After a workstream is created Dataverse provisions its routing contract (a decision contract
        /// set on the workstream some 15-20 seconds later). Waiting for it keeps the link pass, which sets
        /// the contract the moved rulesets use, from being overwritten.
        /// </summary>
        /// <returns>The routing contract Dataverse provisioned, or null when it did not appear in time.</returns>
        static LookupValue WaitForProvisioning(IDataverse target, TableSchema schema, Guid id, RunOptions options)
        {
            if (!schema.Attributes.ContainsKey("msdyn_routingcontractid")) return new LookupValue("msdyn_decisioncontract", Guid.Empty);
            var deadline = options.Now().AddSeconds(options.ProvisioningTimeoutSeconds);
            while (options.Now() < deadline && !options.Cancel.IsCancellationRequested)
            {
                var contract = target.Retrieve(schema, id, new[] { "msdyn_routingcontractid" })?.GetLookup("msdyn_routingcontractid");
                if (contract != null) return contract;
                options.Sleep(TimeSpan.FromSeconds(3));
            }
            return null;
        }

        static SnapshotEntry SnapshotOf(Record trec, TablePlan tplan, Guid id, PlanOperation o)
        {
            var e = new SnapshotEntry { Table = tplan.LogicalName, Id = id, Label = o.FullName, Order = o.Order };
            foreach (var col in tplan.DataColumns)
                if (tplan.TargetSchema.Attributes.TryGetValue(col, out var a) && a.Update) e.Data[col] = trec.Get(col);
            foreach (var lk in tplan.Lookups)
            {
                if (!tplan.TargetSchema.Attributes.TryGetValue(lk.Column, out var a) || !a.Update) continue;
                var lv = trec.GetLookup(lk.Column);
                e.Lookups[lk.Column] = lv == null ? null : new SnapshotLookup { Table = lv.Table ?? lk.Target, Id = lv.Id };
            }
            return e;
        }
    }
}
