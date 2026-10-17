using System;
using System.Collections.Generic;
using System.Linq;
using CcAlm.Core.Model;

namespace CcAlm.Core.Engine
{
    /// <summary>A lookup to another moved table.</summary>
    public sealed class PlanLookup
    {
        public string Column { get; set; }
        public string Target { get; set; }
        public string Label { get; set; }
        public bool Required { get; set; }
        public bool Writable { get; set; }
        /// <summary>
        /// Points at a table written at or after this one (a workstream's default queue): it cannot be
        /// set when the record is first written and is linked in a final pass.
        /// </summary>
        public bool Deferred { get; set; }
    }

    /// <summary>A required lookup to a record provisioned per environment (an SMS number).</summary>
    public sealed class ExternalLookup
    {
        public string Column { get; set; }
        public string Label { get; set; }
    }

    /// <summary>
    /// For one manifest table between one source and one target: what gets read, compared and
    /// written. Data columns present in both orgs, lookups to other manifest tables (and which are
    /// deferred), required lookups to per-environment records, and the columns the target lacks.
    /// </summary>
    public sealed class TablePlan
    {
        public ManifestTable Table { get; set; }
        public bool Usable { get; set; }
        /// <summary>Set for the links of a many-to-many relationship (Move "associate").</summary>
        public AssociationDef Association { get; set; }
        public string Reason { get; set; }
        public string LogicalName => Table.LogicalName;
        public TableSchema SourceSchema { get; set; }
        public TableSchema TargetSchema { get; set; }
        public string PrimaryId { get; set; }
        public string PrimaryName { get; set; }
        public List<string> DataColumns { get; } = new List<string>();
        public List<PlanLookup> Lookups { get; } = new List<PlanLookup>();
        public List<ExternalLookup> RequiredExternal { get; } = new List<ExternalLookup>();
        public List<string> MissingInTarget { get; } = new List<string>();
        /// <summary>Columns to read (lookups by column name); all exist in both orgs.</summary>
        public List<string> Select { get; } = new List<string>();

        public PlanLookup LookupFor(string column) => Lookups.FirstOrDefault(l => string.Equals(l.Column, column, StringComparison.OrdinalIgnoreCase));

        public string ColumnLabel(string column)
        {
            var bare = Values.Bare(column);
            return SourceSchema != null && SourceSchema.Attributes.TryGetValue(bare, out var a) ? a.Label : bare;
        }

        // Attribute types that are never data to compare or write.
        static readonly HashSet<string> NonData = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "Lookup", "Customer", "Owner", "Uniqueidentifier", "Virtual", "EntityName", "PartyList",
            "ManagedProperty", "CalendarRules", "State", "Status", "Image", "File"
        };

        public static TablePlan Resolve(ManifestTable table, TableSchema source, TableSchema target, Manifest manifest, IDictionary<string, ManifestTable> byLogical)
        {
            var plan = new TablePlan { Table = table, SourceSchema = source, TargetSchema = target };
            if (!source.Exists || !target.Exists)
            {
                var where = !source.Exists && !target.Exists ? "either environment" : !source.Exists ? "the source environment" : "the target environment";
                plan.Usable = false;
                plan.Reason = $"{table.DisplayLabel} is not installed in {where}.";
                return plan;
            }

            var exclude = new HashSet<string>(
                manifest.SystemColumns.Concat(manifest.ExcludeColumns).Concat(table.Exclude ?? new List<string>()).Concat(table.StripColumns ?? new List<string>())
                    .Where(c => !string.IsNullOrEmpty(c)).Select(c => Values.Bare(c).ToLowerInvariant()));
            var pk = source.PrimaryId;
            plan.PrimaryId = pk;
            plan.PrimaryName = source.PrimaryName;

            foreach (var a in source.Attributes.Values)
            {
                if (!a.Read || !(a.Create || a.Update)) continue;
                if (string.Equals(a.Name, pk, StringComparison.OrdinalIgnoreCase)) continue;
                if (NonData.Contains(a.Type)) continue;
                if (exclude.Contains(a.Name.ToLowerInvariant())) continue;
                if (!target.Attributes.ContainsKey(a.Name)) { plan.MissingInTarget.Add(a.Name); continue; }
                plan.DataColumns.Add(a.Name);
            }
            plan.DataColumns.Sort(StringComparer.Ordinal);

            foreach (var lk in source.Lookups.Values)
            {
                var col = lk.Column;
                if (!source.Attributes.TryGetValue(col, out var attr) || !attr.Read) continue;
                if (exclude.Contains(col.ToLowerInvariant())) continue;
                if (string.Equals(col, pk, StringComparison.OrdinalIgnoreCase)) continue;

                var managed = lk.Targets.Where(byLogical.ContainsKey).ToList();
                if (managed.Count == 1)
                {
                    if (!target.Lookups.ContainsKey(col)) { plan.MissingInTarget.Add(col); continue; }
                    var targetTable = byLogical[managed[0]];
                    plan.Lookups.Add(new PlanLookup
                    {
                        Column = col,
                        Target = managed[0],
                        Label = attr.Label,
                        Required = attr.Required,
                        Writable = attr.Create || attr.Update,
                        Deferred = targetTable.Order >= table.Order,
                    });
                }
                else if (managed.Count == 0 && attr.Required && attr.Create)
                {
                    plan.RequiredExternal.Add(new ExternalLookup { Column = col, Label = attr.Label });
                }
            }
            plan.Lookups.Sort((x, y) => string.CompareOrdinal(x.Column, y.Column));

            foreach (var k in table.MatchKeys)
            {
                var bare = Values.Bare(k);
                if (!source.Attributes.ContainsKey(bare))
                {
                    plan.Usable = false;
                    plan.Reason = $"{table.DisplayLabel} cannot be matched: column {bare} does not exist in this org. The manifest needs updating.";
                    return plan;
                }
            }

            // What to read: the key, every data column and lookup, and what matching, filtering and
            // the detect-only signals use. A column must exist in both orgs, or the other read fails.
            var select = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { pk };
            if (!string.IsNullOrEmpty(source.PrimaryName)) select.Add(source.PrimaryName);
            foreach (var c in plan.DataColumns) select.Add(c);
            foreach (var l in plan.Lookups) select.Add(l.Column);
            foreach (var k in table.MatchKeys) select.Add(Values.Bare(k));
            if (!string.IsNullOrEmpty(table.TieBreaker)) select.Add(table.TieBreaker);
            if (!string.IsNullOrEmpty(table.PersonalFilterColumn)) select.Add(table.PersonalFilterColumn);
            if (source.Attributes.ContainsKey("ismanaged")) select.Add("ismanaged");
            foreach (var tr in table.TextReferences ?? new List<TextReference>())
                foreach (var c in TextReferenceColumns(tr, source)) select.Add(c);
            foreach (var rule in manifest.DetectOnly.Where(r => r.LogicalName == table.LogicalName))
                if (source.Attributes.ContainsKey(rule.Signal)) select.Add(rule.Signal);
            plan.Select.AddRange(select.Where(c => source.Attributes.ContainsKey(c) && target.Attributes.ContainsKey(c)).OrderBy(c => c, StringComparer.Ordinal));

            plan.Usable = true;
            return plan;
        }

        /// <summary>A text reference names its column(s) exactly or with a trailing *.</summary>
        public static IEnumerable<string> TextReferenceColumns(TextReference reference, TableSchema schema)
        {
            var pattern = reference.Columns ?? "";
            if (pattern.EndsWith("*", StringComparison.Ordinal))
            {
                var prefix = pattern.TrimEnd('*');
                return schema.Attributes.Values
                    .Where(a => a.Name.StartsWith(prefix, StringComparison.OrdinalIgnoreCase) && (a.Type == "String" || a.Type == "Memo"))
                    .Select(a => a.Name).OrderBy(n => n, StringComparer.Ordinal).ToList();
            }
            return schema.Attributes.ContainsKey(pattern) ? new[] { pattern } : Array.Empty<string>();
        }
    }
}
