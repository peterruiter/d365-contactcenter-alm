using System;
using System.Collections.Generic;
using System.Linq;
using CcAlm.Core.Model;

namespace CcAlm.Core.Engine
{
    public sealed class VerificationField
    {
        public string Label { get; set; }
        public string Source { get; set; }
        public string Target { get; set; }
        /// <summary>Why it cannot match, when Dataverse is the reason.</summary>
        public string Note { get; set; }
    }

    public sealed class VerificationDifference
    {
        public string Table { get; set; }
        public string TableLabel { get; set; }
        public string DisplayName { get; set; }
        public string Context { get; set; }
        /// <summary>Changed, Missing, Ambiguous or NotFound.</summary>
        public string Status { get; set; }
        public string Message { get; set; }
        public List<VerificationField> Fields { get; set; } = new List<VerificationField>();
        public string FullName => string.IsNullOrEmpty(Context) ? DisplayName : $"{Context} › {DisplayName}";
    }

    public sealed class VerificationAdded
    {
        public string Table { get; set; }
        public string TableLabel { get; set; }
        public string DisplayName { get; set; }
        public string Context { get; set; }
        public string FullName => string.IsNullOrEmpty(Context) ? DisplayName : $"{Context} › {DisplayName}";
    }

    /// <summary>After an apply: the target compared again against the source, record by record.</summary>
    public sealed class Verification
    {
        /// <summary>Verified, Differences or Error.</summary>
        public string State { get; set; }
        public DateTime CheckedAt { get; set; }
        public int Checked { get; set; }
        public int Matched { get; set; }
        public List<VerificationDifference> Differences { get; set; } = new List<VerificationDifference>();
        /// <summary>Records that appeared in the target during the run without being in the source.</summary>
        public List<VerificationAdded> Added { get; set; } = new List<VerificationAdded>();
        public string Message { get; set; }

        /// <summary>Every "table|key" only in the target, taken before a run writes.</summary>
        public static HashSet<string> ExtraRefs(DiffModel diff) =>
            new HashSet<string>(diff.AllRecords.Where(r => r.Status == RecordStatus.ExtraInTarget).Select(r => r.Ref));

        /// <summary>
        /// Checks an applied run against a fresh compare: every record it created, updated or linked
        /// should now be the same in the target as in the source.
        /// </summary>
        public static Verification Check(DiffModel after, IEnumerable<RunItem> items, ISet<string> extraBefore)
        {
            var plans = after.TablePlans;
            var written = new Dictionary<string, RunItem>();
            foreach (var i in items.Where(x => Outcome.IsWrite(x.Outcome) && !string.IsNullOrEmpty(x.MatchKey)))
            {
                if (!written.ContainsKey(i.Ref) || i.Op == "create" || i.Op == "update") written[i.Ref] = i;
            }

            var v = new Verification { CheckedAt = DateTime.UtcNow, Checked = written.Count };
            foreach (var kv in written)
            {
                var i = kv.Value;
                var row = after.Find(kv.Key);
                var d = new VerificationDifference { Table = i.Table, TableLabel = i.TableLabel, DisplayName = i.DisplayName, Context = i.Context };
                if (row == null) { d.Status = "NotFound"; d.Message = "Not found in either environment when checked afterwards."; v.Differences.Add(d); continue; }
                switch (row.Status)
                {
                    case RecordStatus.Equal: v.Matched++; break;
                    case RecordStatus.Changed:
                        var attrs = plans.TryGetValue(i.Table, out var p) ? p.TargetSchema.Attributes : new Dictionary<string, AttributeInfo>();
                        d.Status = "Changed";
                        d.Message = "Still differs from the source.";
                        foreach (var f in row.Fields)
                        {
                            attrs.TryGetValue(Values.Bare(f.Name), out var a);
                            string note = null;
                            if (a != null && i.Op == "update" && !a.Update) note = "Dataverse does not allow changing this after the record is created.";
                            else if (a != null && i.Op == "create" && !a.Create) note = "Dataverse does not allow setting this when a record is created, so the new record has its default. Change it in the target if it matters.";
                            d.Fields.Add(new VerificationField { Label = f.Label, Source = f.Source, Target = f.Target, Note = note });
                        }
                        v.Differences.Add(d);
                        break;
                    case RecordStatus.MissingInTarget:
                        d.Status = "Missing"; d.Message = "Not found in the target, although it was written. Dataverse may have renamed or removed it."; v.Differences.Add(d); break;
                    case RecordStatus.Ambiguous:
                        d.Status = "Ambiguous"; d.Message = row.Note; v.Differences.Add(d); break;
                    default:
                        d.Status = row.Status; d.Message = $"Its status is {row.Status}."; v.Differences.Add(d); break;
                }
            }

            if (extraBefore != null)
                foreach (var t in after.Tables)
                    foreach (var r in t.Records.Where(x => x.Status == RecordStatus.ExtraInTarget && !extraBefore.Contains(x.Ref)))
                        v.Added.Add(new VerificationAdded { Table = t.Table, TableLabel = t.Label, DisplayName = r.DisplayName, Context = r.Context });

            v.State = v.Differences.Count == 0 ? "Verified" : "Differences";
            return v;
        }
    }

    public sealed class RollbackResult
    {
        public int Restored { get; set; }
        public int Deleted { get; set; }
        public List<string> Unresolved { get; set; } = new List<string>();
    }

    /// <summary>
    /// Undoes an applied run from its snapshot: writes the recorded state back onto every record the
    /// run changed, then deletes the records it created, children before parents.
    /// </summary>
    public static class Rollback
    {
        public static RollbackResult Restore(Snapshot snapshot, IDataverse target, Func<string, TableSchema> schemaOf, IProgress<string> progress = null)
        {
            var result = new RollbackResult();
            foreach (var e in snapshot.Updated)
            {
                progress?.Report($"Restoring {e.Label}");
                try
                {
                    var values = new Dictionary<string, object>(StringComparer.OrdinalIgnoreCase);
                    foreach (var kv in e.Data) values[kv.Key] = kv.Value;
                    foreach (var kv in e.Lookups) values[kv.Key] = kv.Value == null ? null : new LookupValue(kv.Value.Table, kv.Value.Id);
                    target.Update(schemaOf(e.Table), e.Id, values);
                    result.Restored++;
                }
                catch (Exception ex) { result.Unresolved.Add($"Could not restore '{e.Label}': {ex.Message}"); }
            }
            foreach (var c in snapshot.Created.OrderByDescending(x => x.Order))
            {
                progress?.Report($"Deleting {c.Label}");
                try { target.Delete(schemaOf(c.Table), c.Id); result.Deleted++; }
                catch (Exception ex)
                {
                    // Already gone with its parent.
                    if (ex.Message.IndexOf("does not exist", StringComparison.OrdinalIgnoreCase) >= 0) { result.Deleted++; continue; }
                    result.Unresolved.Add($"Could not delete '{c.Label}': {ex.Message}");
                }
            }
            return result;
        }
    }
}
