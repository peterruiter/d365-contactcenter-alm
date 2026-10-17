using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;
using CcAlm.Core.Model;

namespace CcAlm.Core.Engine
{
    // Natural keys: how "the same record" is recognised in two environments whose GUIDs differ.
    //
    // A key is built from the table's matchKeys. A matchKey that is a lookup (a routing step's parent
    // configuration) is replaced by the parent's own key, recursively, so the key never contains an
    // environment-specific GUID at any depth. Keys that collide inside one environment take the
    // table's tie-breaker; if that still collides the records are Ambiguous and never paired.

    /// <summary>One environment's records, indexed by id and (after SetKeys) by key.</summary>
    public sealed class EnvData
    {
        public EnvData(string side) { Side = side; }
        public string Side { get; }
        public Dictionary<string, List<Record>> Records { get; } = new Dictionary<string, List<Record>>();
        public Dictionary<string, Dictionary<Guid, Record>> ById { get; } = new Dictionary<string, Dictionary<Guid, Record>>();
        public Dictionary<Guid, string> GuidToTable { get; } = new Dictionary<Guid, string>();
        public Dictionary<string, Dictionary<Guid, string>> KeyById { get; } = new Dictionary<string, Dictionary<Guid, string>>();
        public Dictionary<string, Dictionary<string, List<Guid>>> ByKey { get; } = new Dictionary<string, Dictionary<string, List<Guid>>>();

        public static EnvData Build(string side, IDictionary<string, List<Record>> recordsByTable)
        {
            var env = new EnvData(side);
            foreach (var kv in recordsByTable)
            {
                env.Records[kv.Key] = kv.Value;
                var map = new Dictionary<Guid, Record>();
                foreach (var r in kv.Value)
                {
                    if (r.Id == Guid.Empty) continue;
                    map[r.Id] = r;
                    env.GuidToTable[r.Id] = kv.Key;
                }
                env.ById[kv.Key] = map;
            }
            return env;
        }

        public Dictionary<Guid, Record> Table(string logical) => ById.TryGetValue(logical, out var m) ? m : new Dictionary<Guid, Record>();

        /// <summary>The single record with this key, or null when there is none or it is ambiguous.</summary>
        public Record ByKeyOne(string table, string key)
        {
            var id = IdByKey(table, key);
            return id.HasValue ? Table(table)[id.Value] : null;
        }

        public Guid? IdByKey(string table, string key)
        {
            if (!ByKey.TryGetValue(table, out var m) || key == null || !m.TryGetValue(key, out var ids) || ids.Count != 1) return null;
            return ids[0];
        }

        public string KeyOf(string table, Guid id) => KeyById.TryGetValue(table, out var m) && m.TryGetValue(id, out var k) ? k : null;
    }

    /// <summary>The lookups across the two environments.</summary>
    public sealed class Maps
    {
        /// <summary>source guid → what it is.</summary>
        public Dictionary<string, RecordRef> SourceGuidToRef { get; } = new Dictionary<string, RecordRef>();
        public Dictionary<string, RecordRef> TargetGuidToRef { get; } = new Dictionary<string, RecordRef>();
        /// <summary>"table|key" → target guid, for keys that are unambiguous in the target.</summary>
        public Dictionary<string, Guid> TargetKeyToGuid { get; } = new Dictionary<string, Guid>();
        /// <summary>"table|key" → its display name and parent.</summary>
        public Dictionary<string, (string DisplayName, string Context)> Labels { get; } = new Dictionary<string, (string, string)>();

        public Maps CloneForRun()
        {
            var m = new Maps();
            foreach (var kv in SourceGuidToRef) m.SourceGuidToRef[kv.Key] = kv.Value;
            foreach (var kv in TargetGuidToRef) m.TargetGuidToRef[kv.Key] = kv.Value;
            foreach (var kv in TargetKeyToGuid) m.TargetKeyToGuid[kv.Key] = kv.Value;
            foreach (var kv in Labels) m.Labels[kv.Key] = kv.Value;
            return m;
        }
    }

    public static class Keys
    {
        static string KeyPart(Record r, string column, TablePlan plan, EnvData env)
        {
            if (Values.IsLookupKey(column))
            {
                var bare = Values.Bare(column);
                var lv = r.GetLookup(bare);
                if (lv == null) return $"{column}=";
                var refTable = plan.LookupFor(bare)?.Target ?? (env.GuidToTable.TryGetValue(lv.Id, out var t) ? t : null);
                var parentKey = refTable != null ? env.KeyOf(refTable, lv.Id) : null;
                return parentKey != null ? $"{column}=[{parentKey}]" : $"{column}=unresolved:{lv.Id.ToString().ToLowerInvariant()}";
            }
            return $"{column}={Values.Text(r.Get(column)).Trim().ToLowerInvariant()}";
        }

        /// <summary>
        /// Every record's key in both environments, table by table in manifest order (parents first),
        /// with the tie-breaker applied on both sides wherever a base key collides in either.
        /// </summary>
        public static void SetKeys(EnvData source, EnvData target, IEnumerable<ManifestTable> tables, IDictionary<string, TablePlan> plans)
        {
            foreach (var t in tables)
            {
                if (!plans.TryGetValue(t.LogicalName, out var plan) || !plan.Usable) continue;
                var baseKeys = new Dictionary<string, Dictionary<Guid, string>>();
                foreach (var env in new[] { source, target })
                {
                    var m = new Dictionary<Guid, string>();
                    foreach (var kv in env.Table(t.LogicalName))
                        m[kv.Key] = string.Join("|", t.MatchKeys.Select(k => KeyPart(kv.Value, k, plan, env)));
                    baseKeys[env.Side] = m;
                }

                var colliding = new HashSet<string>(baseKeys.Values.SelectMany(m => m.Values.GroupBy(v => v).Where(g => g.Count() > 1).Select(g => g.Key)));

                foreach (var env in new[] { source, target })
                {
                    var keyById = new Dictionary<Guid, string>();
                    var byKey = new Dictionary<string, List<Guid>>();
                    foreach (var kv in baseKeys[env.Side])
                    {
                        var k = kv.Value;
                        if (colliding.Contains(k) && !string.IsNullOrEmpty(t.TieBreaker))
                            k = $"{k}|#{t.TieBreaker}={Values.Text(env.Table(t.LogicalName)[kv.Key].Get(t.TieBreaker)).Trim().ToLowerInvariant()}";
                        keyById[kv.Key] = k;
                        if (!byKey.TryGetValue(k, out var list)) byKey[k] = list = new List<Guid>();
                        list.Add(kv.Key);
                    }
                    env.KeyById[t.LogicalName] = keyById;
                    env.ByKey[t.LogicalName] = byKey;
                }
            }
        }

        public static Maps BuildMaps(EnvData source, EnvData target, IDictionary<string, TablePlan> plans)
        {
            var maps = new Maps();
            foreach (var env in new[] { source, target })
            {
                var guidToRef = env == source ? maps.SourceGuidToRef : maps.TargetGuidToRef;
                foreach (var tableKeys in env.KeyById)
                {
                    var logical = tableKeys.Key;
                    var plan = plans[logical];
                    foreach (var kv in tableKeys.Value)
                    {
                        guidToRef[kv.Key.ToString().ToLowerInvariant()] = new RecordRef(logical, kv.Value);
                        var refKey = $"{logical}|{kv.Value}";
                        if (!maps.Labels.ContainsKey(refKey) || env == source)
                        {
                            var rec = env.Table(logical)[kv.Key];
                            maps.Labels[refKey] = (RecordLabel(rec, plan), RecordContext(rec, plan, env, plans));
                        }
                        if (env == target && env.ByKey[logical][kv.Value].Count == 1) maps.TargetKeyToGuid[refKey] = kv.Key;
                    }
                }
            }
            return maps;
        }

        static readonly Regex TemplateColumn = new Regex(@"\{(\w+)\}", RegexOptions.Compiled);

        /// <summary>What a person calls the record: the display template, the primary name, or the first readable key value.</summary>
        public static string RecordLabel(Record r, TablePlan plan)
        {
            var t = plan.Table;
            if (!string.IsNullOrEmpty(t.DisplayTemplate))
            {
                var label = TemplateColumn.Replace(t.DisplayTemplate, m =>
                {
                    var col = m.Groups[1].Value;
                    var bare = Values.Bare(col);
                    if (r.Formatted.TryGetValue(bare, out var fv) && !string.IsNullOrEmpty(fv)) return fv;
                    var v = r.Get(bare);
                    if (v is LookupValue lv) return lv.Name ?? "";
                    return v == null ? "" : Values.Text(v);
                }).Trim();
                if (label.Length > 0) return label;
            }
            var nameCol = !string.IsNullOrEmpty(t.DisplayColumn) ? t.DisplayColumn : plan.PrimaryName;
            var name = nameCol != null ? r.Get(nameCol) as string : null;
            if (!string.IsNullOrEmpty(name)) return name;
            foreach (var k in t.MatchKeys)
            {
                if (Values.IsLookupKey(k)) continue;
                var v = r.Get(k);
                if (v != null && Values.Text(v).Length > 0) return Values.Text(v);
            }
            return "(unnamed)";
        }

        /// <summary>Where a record lives for tables matched under a parent: "Chat › Contact center routing configuration".</summary>
        public static string RecordContext(Record r, TablePlan plan, EnvData env, IDictionary<string, TablePlan> plans, int depth = 0)
        {
            if (depth > 3) return "";
            foreach (var k in plan.Table.MatchKeys)
            {
                if (!Values.IsLookupKey(k)) continue;
                var bare = Values.Bare(k);
                var lv = r.GetLookup(bare);
                if (lv == null) continue;
                var lk = plan.LookupFor(bare);
                if (lk == null) continue;
                if (!env.Table(lk.Target).TryGetValue(lv.Id, out var parent)) continue;
                var parentPlan = plans[lk.Target];
                var parentLabel = RecordLabel(parent, parentPlan);
                var grand = RecordContext(parent, parentPlan, env, plans, depth + 1);
                return string.IsNullOrEmpty(grand) ? parentLabel : $"{grand} › {parentLabel}";
            }
            return "";
        }

        /// <summary>"routing configuration 'Chat › Contact center routing configuration'" for messages.</summary>
        public static string RefLabel(Maps maps, string entity, string key, IDictionary<string, TablePlan> plans)
        {
            var item = plans != null && plans.TryGetValue(entity, out var p) ? p.Table.ItemLabel : entity;
            if (!maps.Labels.TryGetValue($"{entity}|{key}", out var l)) return $"a {item}";
            var name = string.IsNullOrEmpty(l.Context) ? l.DisplayName : $"{l.Context} › {l.DisplayName}";
            return $"{item} '{name}'";
        }
    }
}
