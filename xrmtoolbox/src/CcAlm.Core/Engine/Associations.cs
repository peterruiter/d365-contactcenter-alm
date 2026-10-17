using System;
using System.Collections.Generic;
using System.Linq;
using CcAlm.Core.Model;

namespace CcAlm.Core.Engine
{
    /// <summary>
    /// A many-to-many relationship between two moved tables (quick replies on workstreams, tags on
    /// quick replies). Its links are not columns of either record: they are read from the intersect
    /// table, compared as records of their own, and written once both ends exist. The end written
    /// first (the lower manifest order) owns the link.
    /// </summary>
    public sealed class AssociationDef
    {
        public ManyToManyInfo Relationship { get; set; }
        public TableSchema SourceIntersect { get; set; }
        public TableSchema TargetIntersect { get; set; }
        public string Owner { get; set; }
        public string Other { get; set; }
        public string Label { get; set; }
        public string Group { get; set; }
        public string SchemaName => Relationship.SchemaName;
    }

    public static class Associations
    {
        public static List<AssociationDef> Plans(Manifest manifest, IDictionary<string, TablePlan> plans, Func<string, TableSchema> sourceSchema, Func<string, TableSchema> targetSchema)
        {
            var byLogical = manifest.Tables.ToDictionary(t => t.LogicalName);
            var defs = new Dictionary<string, AssociationDef>();
            foreach (var t in manifest.Tables)
            {
                if (!plans.TryGetValue(t.LogicalName, out var plan) || !plan.Usable || t.IsReadOnly) continue;
                foreach (var m in plan.SourceSchema.ManyToMany)
                {
                    if (defs.ContainsKey(m.SchemaName) || m.Entity1 == m.Entity2) continue;
                    if (!plans.TryGetValue(m.Entity1, out var p1) || !plans.TryGetValue(m.Entity2, out var p2) || !p1.Usable || !p2.Usable) continue;
                    if (byLogical[m.Entity1].IsReadOnly || byLogical[m.Entity2].IsReadOnly) continue;
                    if (!p1.TargetSchema.ManyToMany.Concat(p2.TargetSchema.ManyToMany).Any(x => x.SchemaName == m.SchemaName)) continue;
                    var si = sourceSchema(m.IntersectEntity);
                    var ti = targetSchema(m.IntersectEntity);
                    if (!si.Exists || !ti.Exists) continue;
                    var owner = byLogical[m.Entity1].Order <= byLogical[m.Entity2].Order ? m.Entity1 : m.Entity2;
                    var other = owner == m.Entity1 ? m.Entity2 : m.Entity1;
                    var ownerLabel = byLogical[owner].DisplayLabel;
                    defs[m.SchemaName] = new AssociationDef
                    {
                        Relationship = m, SourceIntersect = si, TargetIntersect = ti, Owner = owner, Other = other,
                        Label = $"{byLogical[other].DisplayLabel} on {char.ToLowerInvariant(ownerLabel[0])}{ownerLabel.Substring(1)}",
                        Group = byLogical[owner].Group,
                    };
                }
            }
            return defs.Values.ToList();
        }

        /// <summary>A table plan for the links, so plan and run treat them like any other table.</summary>
        public static TablePlan TablePlanFor(AssociationDef def) => new TablePlan
        {
            Table = new ManifestTable { LogicalName = def.SchemaName, Label = def.Label, Item = "link", Group = def.Group, Stage = 99, Order = 99, Move = "associate", MatchKeys = new List<string> { "link" } },
            Usable = true,
            Association = def,
            SourceSchema = new TableSchema { LogicalName = def.SchemaName, Exists = true },
            TargetSchema = new TableSchema { LogicalName = def.SchemaName, Exists = true },
        };

        public static List<(string Id1, string Id2)> Pairs(IEnumerable<Record> rows, ManyToManyInfo m) =>
            rows.Select(r => (Id(r.Get(m.Entity1Attribute)), Id(r.Get(m.Entity2Attribute)))).Where(p => p.Item1 != null && p.Item2 != null).ToList();

        static string Id(object v) => v switch
        {
            null => null,
            Guid g => g.ToString(),
            LookupValue l => l.Id.ToString(),
            _ => v.ToString().ToLowerInvariant(),
        };

        /// <summary>One relationship's links in both environments, paired by what their two ends are.</summary>
        public static TableDiff Compare(AssociationDef def, List<(string Id1, string Id2)> sourcePairs, List<(string Id1, string Id2)> targetPairs, Maps maps, IDictionary<string, TablePlan> plans)
        {
            var m = def.Relationship;
            (string Key, RecordRef Owner, RecordRef Other)? Link((string Id1, string Id2) p, Dictionary<string, RecordRef> guidToRef)
            {
                if (!guidToRef.TryGetValue(p.Id1, out var r1) || !guidToRef.TryGetValue(p.Id2, out var r2)) return null;
                var owner = def.Owner == m.Entity1 ? r1 : r2;
                var other = def.Owner == m.Entity1 ? r2 : r1;
                return ($"{owner.Ref} <> {other.Ref}", owner, other);
            }
            var src = new Dictionary<string, (string Key, RecordRef Owner, RecordRef Other)>();
            foreach (var p in sourcePairs) { var l = Link(p, maps.SourceGuidToRef); if (l.HasValue) src[l.Value.Key] = l.Value; }
            var tgt = new Dictionary<string, (string Key, RecordRef Owner, RecordRef Other)>();
            foreach (var p in targetPairs) { var l = Link(p, maps.TargetGuidToRef); if (l.HasValue) tgt[l.Value.Key] = l.Value; }

            var table = new TableDiff { Table = def.SchemaName, Label = def.Label, Group = def.Group, Stage = 99 };
            RecordDiff Row(string status, (string Key, RecordRef Owner, RecordRef Other) link)
            {
                string Name(RecordRef r) => maps.Labels.TryGetValue(r.Ref, out var l) ? (string.IsNullOrEmpty(l.Context) ? l.DisplayName : $"{l.Context} › {l.DisplayName}") : r.Key;
                var row = new RecordDiff { Table = def.SchemaName, MatchKey = link.Key, Status = status, DisplayName = Name(link.Other), Context = Name(link.Owner) };
                // The owner as a parent (it brings the link); the other end as something the link uses.
                row.DependsOn.Add(new DependencyRef { Table = link.Owner.Entity, MatchKey = link.Owner.Key, Label = Keys.RefLabel(maps, link.Owner.Entity, link.Owner.Key, plans), Via = def.Label, Deferred = false, Kind = "lookup" });
                row.DependsOn.Add(new DependencyRef { Table = link.Other.Entity, MatchKey = link.Other.Key, Label = Keys.RefLabel(maps, link.Other.Entity, link.Other.Key, plans), Via = def.Label, Deferred = true, Kind = "lookup" });
                return row;
            }
            foreach (var kv in src) table.Records.Add(Row(tgt.ContainsKey(kv.Key) ? RecordStatus.Equal : RecordStatus.MissingInTarget, kv.Value));
            foreach (var kv in tgt) if (!src.ContainsKey(kv.Key)) table.Records.Add(Row(RecordStatus.ExtraInTarget, kv.Value));
            return table;
        }
    }
}
