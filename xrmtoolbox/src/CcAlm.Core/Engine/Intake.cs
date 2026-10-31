using System;
using System.Collections.Generic;
using System.Linq;
using System.Xml;
using CcAlm.Core.Model;

namespace CcAlm.Core.Engine
{
    /// <summary>One rule of an intake ruleset; Xml leaves out the id, which differs per environment.</summary>
    public sealed class IntakeRule
    {
        public string Key { get; set; }
        public string Name { get; set; }
        public string Xml { get; set; }
    }

    /// <summary>A record routing hub's intake ruleset in one environment.</summary>
    public sealed class IntakeRuleset
    {
        public Guid HubId { get; set; }
        public string HubKey { get; set; }
        public Guid? RulesetId { get; set; }
        public string Definition { get; set; }
        public List<IntakeRule> Rules { get; } = new List<IntakeRule>();
    }

    /// <summary>Both environments' intake rulesets, by hub key.</summary>
    public sealed class IntakeDef
    {
        public Dictionary<string, IntakeRuleset> Source { get; set; }
        public Dictionary<string, IntakeRuleset> Target { get; set; }
    }

    /// <summary>
    /// Record routing intake rules. Every table with record routing (Case routing hub for incident)
    /// has one intake ruleset, and each rule in it sends the records it matches to one workstream.
    /// That ruleset is shared by all of the table's workstreams and often comes with a managed
    /// solution, so it is not moved as a whole: its rules are compared one by one ("Intake rules"),
    /// each sits under the workstream it routes to and is ticked with it, and a run merges the
    /// selected rules into the target's own intake ruleset. The target's other rules stay as they
    /// are, in their order.
    /// </summary>
    public static class Intake
    {
        public const string Table = "intakerule";
        public const string HubTable = "msdyn_masterentityroutingconfiguration";
        public const string RulesetTable = "msdyn_decisionruleset";
        public const string Label = "Intake rules";

        public static Dictionary<string, IntakeRuleset> Rulesets(EnvData env)
        {
            var result = new Dictionary<string, IntakeRuleset>();
            var rulesets = env.Table(RulesetTable);
            foreach (var kv in env.Table(HubTable))
            {
                var key = env.KeyOf(HubTable, kv.Key);
                if (key == null || env.IdByKey(HubTable, key) == null) continue;
                var rsId = kv.Value.GetLookup("msdyn_rulesetid")?.Id;
                var rs = rsId.HasValue && rulesets.TryGetValue(rsId.Value, out var r) ? r : null;
                var set = new IntakeRuleset { HubId = kv.Key, HubKey = key, RulesetId = rs != null ? rsId : null, Definition = rs?.Get("msdyn_rulesetdefinition") as string };
                set.Rules.AddRange(RuleList(set.Definition));
                result[key] = set;
            }
            return result;
        }

        /// <summary>A rule is known by its name, as the admin center shows it; the id differs per environment.</summary>
        public static string RuleKey(XmlElement rule)
        {
            var name = rule.GetAttribute("name");
            return string.IsNullOrWhiteSpace(name) ? "id=" + rule.GetAttribute("id").ToLowerInvariant() : "name=" + name.Trim().ToLowerInvariant();
        }

        public static List<IntakeRule> RuleList(string definition)
        {
            var list = new List<IntakeRule>();
            if (string.IsNullOrEmpty(definition)) return list;
            var doc = new XmlDocument();
            try { doc.LoadXml(definition); } catch (XmlException) { return list; }
            foreach (XmlElement r in doc.SelectNodes("//rules/rule"))
            {
                var c = (XmlElement)r.CloneNode(true);
                c.Attributes.RemoveNamedItem("id");
                list.Add(new IntakeRule { Key = RuleKey(r), Name = r.GetAttribute("name").Trim(), Xml = c.OuterXml });
            }
            return list;
        }

        /// <summary>A table plan for the rules: written after the workstreams they route to, into the target's ruleset.</summary>
        public static TablePlan TablePlanFor(IntakeDef def, TablePlan rulesetPlan) => new TablePlan
        {
            Table = new ManifestTable { LogicalName = Table, Label = Label, Item = "intake rule", Group = "Workstreams", Stage = 98, Order = 98, Move = "intake", MatchKeys = new List<string> { "rule" } },
            Usable = true,
            Intake = def,
            SourceSchema = new TableSchema { LogicalName = Table, Exists = true },
            TargetSchema = rulesetPlan.TargetSchema,
        };

        /// <summary>"table|key" of every intake ruleset in either environment, which the ruleset table leaves out.</summary>
        public static HashSet<string> RulesetRefs(IntakeDef def, EnvData source, EnvData target)
        {
            var refs = new HashSet<string>();
            foreach (var (sets, env) in new[] { (def.Source, source), (def.Target, target) })
                foreach (var s in sets.Values)
                    if (s.RulesetId.HasValue) refs.Add($"{RulesetTable}|{env.KeyOf(RulesetTable, s.RulesetId.Value)}");
            return refs;
        }

        public static (string HubKey, string RuleKey) SplitKey(string matchKey)
        {
            var at = matchKey.IndexOf("|name=", StringComparison.Ordinal);
            if (at < 0) at = matchKey.IndexOf("|id=", StringComparison.Ordinal);
            return at < 0 ? (matchKey, "") : (matchKey.Substring(0, at), matchKey.Substring(at + 1));
        }

        /// <summary>Every hub's intake rules in both environments, paired by hub and rule name.</summary>
        public static TableDiff Compare(IntakeDef def, Maps maps, IDictionary<string, TablePlan> plans)
        {
            var table = new TableDiff { Table = Table, Label = Label, Group = "Workstreams", Stage = 98 };
            foreach (var hubKey in def.Source.Keys.Concat(def.Target.Keys).Distinct())
            {
                var hubLabel = maps.Labels.TryGetValue($"{HubTable}|{hubKey}", out var hl) ? hl.DisplayName : hubKey;
                var src = def.Source.TryGetValue(hubKey, out var s) ? s.Rules : new List<IntakeRule>();
                var tgt = def.Target.TryGetValue(hubKey, out var t) ? t.Rules : new List<IntakeRule>();
                var srcCount = src.GroupBy(r => r.Key).ToDictionary(g => g.Key, g => g.Count());
                var tgtByKey = tgt.GroupBy(r => r.Key).ToDictionary(g => g.Key, g => g.ToList());

                RecordDiff Row(string status, IntakeRule rule, FieldDiff field, List<DependencyRef> deps, string note)
                {
                    var key = $"{hubKey}|{rule.Key}";
                    maps.Labels[$"{Table}|{key}"] = (rule.Name, hubLabel);
                    var row = new RecordDiff { Table = Table, MatchKey = key, Status = status, DisplayName = rule.Name, Context = hubLabel, Note = note };
                    if (field != null) row.Fields.Add(field);
                    if (deps != null) row.DependsOn.AddRange(deps);
                    return row;
                }

                var seen = new HashSet<string>();
                foreach (var rule in src)
                {
                    if (!seen.Add(rule.Key)) continue;
                    var inTarget = tgtByKey.TryGetValue(rule.Key, out var tRules);
                    if (srcCount[rule.Key] > 1 || (inTarget && tRules.Count > 1))
                    {
                        var where = srcCount[rule.Key] > 1 ? "source" : "target";
                        var n = where == "source" ? srcCount[rule.Key] : tRules.Count;
                        table.Records.Add(Row(RecordStatus.Ambiguous, rule, null, null, $"{n} intake rules of {hubLabel} in the {where} have the same name, so they cannot be told apart. Rename one there."));
                        continue;
                    }
                    var deps = Dependencies(rule, hubKey, maps, plans);
                    if (!inTarget) { table.Records.Add(Row(RecordStatus.MissingInTarget, rule, null, deps, null)); continue; }
                    var sN = References.Normalise(rule.Xml, maps.SourceGuidToRef);
                    var tN = References.Normalise(tRules[0].Xml, maps.TargetGuidToRef);
                    if (Values.Same(sN.Text, tN.Text)) { table.Records.Add(Row(RecordStatus.Equal, rule, null, deps, null)); continue; }
                    string Labels(IEnumerable<string> refs) => string.Join(", ", refs.Select(x => { var p = x.Split(new[] { '|' }, 2); return Keys.RefLabel(maps, p[0], p[1], plans); }));
                    var added = sN.Refs.Where(x => !tN.Refs.Contains(x)).ToList();
                    var removed = tN.Refs.Where(x => !sN.Refs.Contains(x)).ToList();
                    var summary = new List<string>();
                    if (added.Count > 0) summary.Add("now routes to " + Labels(added));
                    if (removed.Count > 0) summary.Add("no longer routes to " + Labels(removed));
                    if (summary.Count == 0) summary.Add("rule conditions differ");
                    table.Records.Add(Row(RecordStatus.Changed, rule, new FieldDiff { Name = "rule", Label = "Rule", Kind = "definition", Source = string.Join("; ", summary) }, deps, null));
                }
                foreach (var rule in tgt)
                    if (seen.Add(rule.Key)) table.Records.Add(Row(RecordStatus.ExtraInTarget, rule, null, null, null));
            }
            return table;
        }

        /// <summary>The workstream a rule routes to first (where it sits), then its hub, then anything else its conditions name.</summary>
        static List<DependencyRef> Dependencies(IntakeRule rule, string hubKey, Maps maps, IDictionary<string, TablePlan> plans)
        {
            var refs = References.Guids(rule.Xml).Select(g => maps.SourceGuidToRef.TryGetValue(g, out var r) ? r : null).Where(r => r != null).ToList();
            var ordered = refs.Where(r => r.Entity == "msdyn_liveworkstream")
                .Concat(new[] { new RecordRef(HubTable, hubKey) })
                .Concat(refs.Where(r => r.Entity != "msdyn_liveworkstream"));
            var deps = new List<DependencyRef>();
            var seen = new HashSet<string>();
            foreach (var r in ordered)
            {
                if (!seen.Add(r.Ref)) continue;
                var isWorkstream = r.Entity == "msdyn_liveworkstream";
                deps.Add(new DependencyRef
                {
                    Table = r.Entity, MatchKey = r.Key, Label = Keys.RefLabel(maps, r.Entity, r.Key, plans),
                    Via = r.Entity == HubTable ? "Record routing hub" : "Intake rule", Deferred = false,
                    Kind = isWorkstream || r.Entity == HubTable ? "lookup" : "embedded",
                    // The first workstream is where the rule sits.
                    Owner = isWorkstream && !deps.Any(d => d.Owner),
                });
            }
            return deps;
        }

        /// <summary>
        /// The target's intake ruleset definition with one rule from the source put in: in place of the
        /// target's rule of the same name (keeping its id), else straight after the nearest rule that
        /// comes before it in the source, else first. The first rule that matches a record wins, so
        /// where it goes matters.
        /// </summary>
        public static string Merge(string targetDefinition, string ruleXml, string ruleKey, IList<string> sourceOrder)
        {
            var doc = new XmlDocument { PreserveWhitespace = true };
            doc.LoadXml(targetDefinition);
            var rulesNode = doc.SelectSingleNode("//rules") ?? throw new DataverseException("The target intake ruleset has no rules element.");
            var frag = new XmlDocument();
            frag.LoadXml(ruleXml);
            var added = (XmlElement)doc.ImportNode(frag.DocumentElement, true);

            var existing = rulesNode.SelectNodes("rule").Cast<XmlElement>().ToList();
            var byKey = new Dictionary<string, XmlElement>();
            foreach (var r in existing) if (!byKey.ContainsKey(RuleKey(r))) byKey[RuleKey(r)] = r;
            if (byKey.TryGetValue(ruleKey, out var old))
            {
                added.SetAttribute("id", old.GetAttribute("id"));
                rulesNode.ReplaceChild(added, old);
                return doc.OuterXml;
            }
            added.SetAttribute("id", Guid.NewGuid().ToString());
            for (var j = sourceOrder.IndexOf(ruleKey) - 1; j >= 0; j--)
                if (byKey.TryGetValue(sourceOrder[j], out var before)) { rulesNode.InsertAfter(added, before); return doc.OuterXml; }
            if (existing.Count > 0) rulesNode.InsertBefore(added, existing[0]);
            else rulesNode.AppendChild(added);
            return doc.OuterXml;
        }

        /// <summary>The source rule an operation writes, with its GUIDs rewritten for the target, or why it cannot be.</summary>
        public static (string HubKey, string RuleKey, string Xml, List<string> Order, string Problem) SourceRule(TablePlan plan, string matchKey, Maps maps, IDictionary<string, TablePlan> plans)
        {
            var (hubKey, ruleKey) = SplitKey(matchKey);
            var rule = plan.Intake.Source.TryGetValue(hubKey, out var set) ? set.Rules.FirstOrDefault(r => r.Key == ruleKey) : null;
            if (rule == null) return (hubKey, ruleKey, null, new List<string>(), "The source rule could not be found any more. Compare again.");
            var rw = References.ToTarget(rule.Xml, maps.SourceGuidToRef, maps.TargetKeyToGuid);
            string problem = null;
            if (rw.Unmapped.Count > 0)
                problem = $"It routes to or names {string.Join(", ", rw.Unmapped.Select(u => Keys.RefLabel(maps, u.Entity, u.Key, plans)).Distinct())}, not in the target.";
            return (hubKey, ruleKey, rw.Text, set.Rules.Select(r => r.Key).ToList(), problem);
        }
    }
}
