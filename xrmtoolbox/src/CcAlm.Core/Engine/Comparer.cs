using System;
using System.Collections.Generic;
using System.Linq;
using CcAlm.Core.Model;

namespace CcAlm.Core.Engine
{
    /// <summary>Reads both environments, pairs the records and diffs them.</summary>
    public static class Comparer
    {
        /// <summary>
        /// Compares source and target over every manifest table. sourceReads/targetReads: what an
        /// earlier compare read (EnvReads); their tables are not read again. A run passes the
        /// source's to read only the target, which is the one thing that must be current before it
        /// writes. progress gets a line per table.
        /// </summary>
        public static DiffModel Compare(Manifest manifest, IDataverse source, IDataverse target,
            EnvReads sourceReads = null, EnvReads targetReads = null, Action<string> progress = null, IEnumerable<string> onlyTables = null)
        {
            var byLogical = manifest.Tables.ToDictionary(t => t.LogicalName);
            var sReads = sourceReads ?? new EnvReads { Url = source.Url, ReadAt = DateTime.UtcNow };
            var tReads = targetReads ?? new EnvReads { Url = target.Url, ReadAt = DateTime.UtcNow };
            var diff = new DiffModel
            {
                DiffId = "dif_" + Guid.NewGuid().ToString("N").Substring(0, 12),
                SourceName = source.Name,
                TargetName = target.Name,
                Generated = DateTime.UtcNow,
                Manifest = manifest,
                TablePlans = new Dictionary<string, TablePlan>(),
                SourceReads = sReads,
                TargetReads = tReads,
            };

            // Every table is read even for a narrowed diff: children are keyed by their parents and
            // lookups resolve through them.
            int n = 0;
            foreach (var t in manifest.Tables)
            {
                n++;
                progress?.Invoke($"Reading {t.DisplayLabel} ({n} of {manifest.Tables.Count})");
                var ss = Schema(source, sReads, t.LogicalName);
                var ts = Schema(target, tReads, t.LogicalName);
                var plan = TablePlan.Resolve(t, ss, ts, manifest, byLogical);
                diff.TablePlans[t.LogicalName] = plan;
                if (!plan.Usable)
                {
                    sReads.Records[t.LogicalName] = sReads.Records.TryGetValue(t.LogicalName, out var keep) ? keep : new List<Record>();
                    if (t.Move != "reference") diff.Notices.Add(new Notice { Severity = "info", Table = t.LogicalName, Message = plan.Reason });
                    continue;
                }
                if (plan.MissingInTarget.Count > 0)
                {
                    var labels = plan.MissingInTarget.Take(6).Select(plan.ColumnLabel).ToList();
                    var more = plan.MissingInTarget.Count > 6 ? $" and {plan.MissingInTarget.Count - 6} more" : "";
                    diff.Notices.Add(new Notice { Severity = "warning", Table = t.LogicalName, Message = $"The target has an older version of {t.DisplayLabel}: {string.Join(", ", labels)}{more} do not exist there and will not be copied." });
                }
                if (!sReads.Records.ContainsKey(t.LogicalName)) sReads.Records[t.LogicalName] = Read(source, plan, plan.SourceSchema);
                if (!tReads.Records.ContainsKey(t.LogicalName)) tReads.Records[t.LogicalName] = Read(target, plan, plan.TargetSchema);
            }

            progress?.Invoke("Pairing the records");
            var sourceRecords = new Dictionary<string, List<Record>>();
            var targetRecords = new Dictionary<string, List<Record>>();
            foreach (var t in manifest.Tables)
            {
                var plan = diff.TablePlans[t.LogicalName];
                sourceRecords[t.LogicalName] = plan.Usable ? sReads.Records[t.LogicalName] : new List<Record>();
                targetRecords[t.LogicalName] = plan.Usable ? tReads.Records[t.LogicalName] : new List<Record>();
            }
            diff.Source = EnvData.Build("source", sourceRecords);
            diff.Target = EnvData.Build("target", targetRecords);
            Keys.SetKeys(diff.Source, diff.Target, manifest.Tables, diff.TablePlans);
            diff.Maps = Keys.BuildMaps(diff.Source, diff.Target, diff.TablePlans);

            var only = onlyTables == null ? null : new HashSet<string>(onlyTables);
            foreach (var t in manifest.Tables)
            {
                if (t.IsReadOnly) continue;
                if (only != null && !only.Contains(t.LogicalName)) continue;
                var plan = diff.TablePlans[t.LogicalName];
                if (!plan.Usable) continue;
                diff.Tables.Add(CompareTable(plan, diff.Source, diff.Target, diff.Maps, diff.TablePlans));
            }
            // Many-to-many links between moved records (quick replies on workstreams), as tables of their own.
            foreach (var def in Associations.Plans(manifest, diff.TablePlans, l => Schema(source, sReads, l), l => Schema(target, tReads, l)))
            {
                diff.TablePlans[def.SchemaName] = Associations.TablePlanFor(def);
                var m = def.Relationship;
                if (only != null && !only.Contains(def.SchemaName) && !only.Contains(m.Entity1) && !only.Contains(m.Entity2)) continue;
                var cols = new[] { m.Entity1Attribute, m.Entity2Attribute };
                if (!sReads.Records.ContainsKey(def.SchemaName)) sReads.Records[def.SchemaName] = source.GetRecords(def.SourceIntersect, cols).ToList();
                if (!tReads.Records.ContainsKey(def.SchemaName)) tReads.Records[def.SchemaName] = target.GetRecords(def.TargetIntersect, cols).ToList();
                diff.Tables.Add(Associations.Compare(def, Associations.Pairs(sReads.Records[def.SchemaName], m), Associations.Pairs(tReads.Records[def.SchemaName], m), diff.Maps, diff.TablePlans));
            }
            diff.DetectOnly.AddRange(DetectOnly(manifest, diff.Source, diff.Target, diff.TablePlans));

            var all = diff.AllRecords.ToList();
            diff.Summary = new DiffSummary
            {
                MissingInTarget = all.Count(r => r.Status == RecordStatus.MissingInTarget),
                ExtraInTarget = all.Count(r => r.Status == RecordStatus.ExtraInTarget),
                Changed = all.Count(r => r.Status == RecordStatus.Changed),
                Equal = all.Count(r => r.Status == RecordStatus.Equal),
                Ambiguous = all.Count(r => r.Status == RecordStatus.Ambiguous),
            };
            return diff;
        }

        static TableSchema Schema(IDataverse env, EnvReads reads, string logical)
        {
            if (!reads.Schemas.TryGetValue(logical, out var s)) reads.Schemas[logical] = s = env.GetTableSchema(logical);
            return s;
        }

        static List<Record> Read(IDataverse env, TablePlan plan, TableSchema schema)
        {
            var t = plan.Table;
            // Personal and system queues: one per user, provisioned by Dataverse, never configuration.
            var rows = string.IsNullOrEmpty(t.PersonalFilterColumn)
                ? env.GetRecords(schema, plan.Select)
                : env.GetRecords(schema, plan.Select, t.PersonalFilterColumn, true);
            return rows.ToList();
        }

        /// <summary>
        /// The records one source record needs in the target before it can be written: every lookup to
        /// another moved table, every template it names by unique name, every record its definition embeds.
        /// </summary>
        public static List<DependencyRef> Dependencies(Record r, TablePlan plan, Maps maps, IDictionary<string, TablePlan> plans)
        {
            var deps = new List<DependencyRef>();
            var seen = new HashSet<string>();
            void Add(string table, string key, string via, bool deferred, string kind)
            {
                if (!seen.Add($"{table}|{key}")) return;
                var label = key.StartsWith("unresolved:", StringComparison.Ordinal)
                    ? $"a {plans[table].Table.ItemLabel} that no longer exists"
                    : Keys.RefLabel(maps, table, key, plans);
                deps.Add(new DependencyRef { Table = table, MatchKey = key, Label = label, Via = via, Deferred = deferred, Kind = kind });
            }

            foreach (var lk in plan.Lookups)
            {
                var lv = r.GetLookup(lk.Column);
                if (lv == null) continue;
                var g = lv.Id.ToString();
                if (maps.SourceGuidToRef.TryGetValue(g, out var rf)) Add(rf.Entity, rf.Key, lk.Label, lk.Deferred, "lookup");
                else Add(lk.Target, "unresolved:" + g, lk.Label, lk.Deferred, "lookup");
            }

            foreach (var tr in plan.Table.TextReferences ?? new List<TextReference>())
            {
                if (!plans.TryGetValue(tr.Target, out var targetPlan) || !targetPlan.Usable) continue;
                foreach (var col in TablePlan.TextReferenceColumns(tr, plan.SourceSchema))
                {
                    var v = r.Get(col) as string;
                    if (string.IsNullOrEmpty(v)) continue;
                    var key = $"{tr.TargetKey}={v.Trim().ToLowerInvariant()}";
                    var via = plan.ColumnLabel(col);
                    if (!string.IsNullOrEmpty(tr.Label)) via = (tr.Columns ?? "").EndsWith("*", StringComparison.Ordinal) ? $"{tr.Label} ({via.ToLowerInvariant()})" : tr.Label;
                    Add(tr.Target, key, via, false, "name");
                }
            }

            foreach (var col in plan.Table.GuidBearingColumns ?? new List<string>())
            {
                foreach (var g in References.Guids(r.Get(col) as string))
                    if (maps.SourceGuidToRef.TryGetValue(g, out var rf)) Add(rf.Entity, rf.Key, plan.ColumnLabel(col), false, "embedded");
            }
            return deps;
        }

        /// <summary>Pairs one table's records by key and classifies each.</summary>
        public static TableDiff CompareTable(TablePlan plan, EnvData source, EnvData target, Maps maps, IDictionary<string, TablePlan> plans)
        {
            var t = plan.Table;
            var logical = t.LogicalName;
            var result = new TableDiff { Table = logical, Label = t.DisplayLabel, Group = t.Group, Stage = t.Stage };
            var srcByKey = source.ByKey.TryGetValue(logical, out var sb) ? sb : new Dictionary<string, List<Guid>>();
            var tgtByKey = target.ByKey.TryGetValue(logical, out var tb) ? tb : new Dictionary<string, List<Guid>>();

            RecordDiff Row(string status, string key, Record src, Record tgt, IEnumerable<FieldDiff> fields, IEnumerable<DependencyRef> deps, string note)
            {
                var rec = src ?? tgt;
                var env = src != null ? source : target;
                var row = new RecordDiff
                {
                    Table = logical, MatchKey = key, Status = status, Note = note,
                    DisplayName = Keys.RecordLabel(rec, plan),
                    Context = Keys.RecordContext(rec, plan, env, plans),
                };
                if (fields != null) row.Fields.AddRange(fields.Where(f => f != null));
                if (deps != null) row.DependsOn.AddRange(deps.Where(d => d != null));
                return row;
            }

            var keyLabels = t.MatchKeys.Select(k => plan.ColumnLabel(k).ToLowerInvariant()).ToList();
            var sameWhat = keyLabels.Count > 1 ? string.Join(", ", keyLabels.Take(keyLabels.Count - 1)) + " and " + keyLabels.Last() : keyLabels[0];
            var allLinks = t.MatchKeys.All(Values.IsLookupKey);
            string DupNote(int count, string where) => allLinks
                ? $"The {where} has {count} identical links between the same records. Delete the extra one there."
                : $"{count} records in the {where} share the same {sameWhat}, so they cannot be told apart. Rename or delete the extra one there.";

            foreach (var kv in srcByKey)
            {
                var key = kv.Key;
                var srcIds = kv.Value;
                var srcRec = source.Table(logical)[srcIds[0]];
                if (srcRec.IsManaged) continue;   // ships with a managed solution in both orgs

                if (srcIds.Count > 1) { result.Records.Add(Row(RecordStatus.Ambiguous, key, srcRec, null, null, null, DupNote(srcIds.Count, "source"))); continue; }
                if (tgtByKey.TryGetValue(key, out var tIds) && tIds.Count > 1) { result.Records.Add(Row(RecordStatus.Ambiguous, key, srcRec, null, null, null, DupNote(tIds.Count, "target"))); continue; }

                var deps = Dependencies(srcRec, plan, maps, plans);
                var copyNote = source.Collapsed.TryGetValue(logical, out var collapsedHere) && collapsedHere.TryGetValue(key, out var copies)
                    ? $"The source has {copies} identical copies of this record; they are moved as one." : null;
                if (!tgtByKey.ContainsKey(key)) { result.Records.Add(Row(RecordStatus.MissingInTarget, key, srcRec, null, null, deps, copyNote)); continue; }

                var tgtRec = target.Table(logical)[tgtByKey[key][0]];
                var fields = new List<FieldDiff>();
                foreach (var col in plan.DataColumns)
                {
                    if ((t.GuidBearingColumns ?? new List<string>()).Contains(col))
                    {
                        var sN = References.Normalise(srcRec.Get(col) as string, maps.SourceGuidToRef);
                        var tN = References.Normalise(tgtRec.Get(col) as string, maps.TargetGuidToRef);
                        if (Values.Same(sN.Text, tN.Text)) continue;
                        var added = sN.Refs.Where(x => !tN.Refs.Contains(x)).ToList();
                        var removed = tN.Refs.Where(x => !sN.Refs.Contains(x)).ToList();
                        var summary = new List<string>();
                        string Labels(IEnumerable<string> refs) => string.Join(", ", refs.Select(x => { var p = x.Split(new[] { '|' }, 2); return Keys.RefLabel(maps, p[0], p[1], plans); }));
                        if (added.Count > 0) summary.Add("now also uses " + Labels(added));
                        if (removed.Count > 0) summary.Add("no longer uses " + Labels(removed));
                        if (summary.Count == 0) summary.Add("rule conditions or order differ");
                        fields.Add(new FieldDiff { Name = col, Label = plan.ColumnLabel(col), Kind = "definition", Source = string.Join("; ", summary) });
                        continue;
                    }
                    if (!Values.Same(srcRec.Get(col), tgtRec.Get(col)))
                        fields.Add(new FieldDiff { Name = col, Label = plan.ColumnLabel(col), Kind = "value", Source = Values.Formatted(srcRec, col), Target = Values.Formatted(tgtRec, col) });
                }

                foreach (var lk in plan.Lookups)
                {
                    var sg = srcRec.GetLookup(lk.Column)?.Id.ToString();
                    var tg = tgtRec.GetLookup(lk.Column)?.Id.ToString();
                    RecordRef sRef = null, tRef = null;
                    if (sg != null) maps.SourceGuidToRef.TryGetValue(sg, out sRef);
                    if (tg != null) maps.TargetGuidToRef.TryGetValue(tg, out tRef);
                    var sKey = sRef != null ? sRef.Ref : sg != null ? "?" + sg : "";
                    var tKey = tRef != null ? tRef.Ref : tg != null ? "?" + tg : "";
                    if (sKey == tKey) continue;
                    var sText = sRef != null ? Keys.RefLabel(maps, sRef.Entity, sRef.Key, plans) : sg != null ? "a record this tool does not move" : "(none)";
                    var tText = tRef != null ? Keys.RefLabel(maps, tRef.Entity, tRef.Key, plans) : tg != null ? "a record this tool does not move" : "(none)";
                    fields.Add(new FieldDiff { Name = lk.Column, Label = lk.Label, Kind = "lookup", Source = sText, Target = tText });
                }

                // Same records report their links too: selecting a workstream with everything under it
                // walks through an unchanged routing configuration to a changed step.
                result.Records.Add(Row(fields.Count > 0 ? RecordStatus.Changed : RecordStatus.Equal, key, srcRec, tgtRec, fields, deps, copyNote));
            }

            foreach (var kv in tgtByKey)
            {
                if (srcByKey.ContainsKey(kv.Key)) continue;
                var tgtRec = target.Table(logical)[kv.Value[0]];
                if (tgtRec.IsManaged) continue;
                result.Records.Add(Row(RecordStatus.ExtraInTarget, kv.Key, null, tgtRec, null, null, null));
            }
            return result;
        }

        /// <summary>
        /// Configuration that cannot move as data (phone numbers, Copilot agents, channel accounts):
        /// each source record carrying the signal whose target record does not carry it yet.
        /// </summary>
        public static List<DetectFinding> DetectOnly(Manifest manifest, EnvData source, EnvData target, IDictionary<string, TablePlan> plans)
        {
            var findings = new List<DetectFinding>();
            foreach (var rule in manifest.DetectOnly)
            {
                if (rule == null || !plans.TryGetValue(rule.LogicalName, out var plan) || !plan.Usable) continue;
                foreach (var kv in source.Table(rule.LogicalName))
                {
                    var row = kv.Value;
                    if (row.IsManaged || !HasSignal(row, rule.Signal)) continue;
                    var key = source.KeyOf(rule.LogicalName, kv.Key);
                    var tgt = target.ByKeyOne(rule.LogicalName, key);
                    if (tgt != null && HasSignal(tgt, rule.Signal)) continue;
                    findings.Add(new DetectFinding { Type = rule.Type, Table = rule.LogicalName, Label = plan.Table.DisplayLabel, Record = Keys.RecordLabel(row, plan), Message = rule.Message });
                }
            }
            return findings;
        }

        static bool HasSignal(Record r, string column)
        {
            var v = r.Get(column);
            return v != null && Values.Text(v).Length > 0;
        }
    }
}
