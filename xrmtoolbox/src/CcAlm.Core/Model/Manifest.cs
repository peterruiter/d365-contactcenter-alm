using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Newtonsoft.Json;

namespace CcAlm.Core.Model
{
    /// <summary>
    /// config/manifest.json (version 2): which tables move, in which order and stage, and how a record
    /// is recognised in another environment. Columns and lookups come from each org's metadata.
    /// </summary>
    public sealed class Manifest
    {
        [JsonProperty("version")] public string Version { get; set; }
        [JsonProperty("systemColumns")] public List<string> SystemColumns { get; set; } = new List<string>();
        [JsonProperty("excludeColumns")] public List<string> ExcludeColumns { get; set; } = new List<string>();
        [JsonProperty("stages")] public List<StageInfo> Stages { get; set; } = new List<StageInfo>();
        [JsonProperty("detectOnly")] public List<DetectRule> DetectOnly { get; set; } = new List<DetectRule>();
        [JsonProperty("tables")] public List<ManifestTable> Tables { get; set; } = new List<ManifestTable>();

        public static readonly string[] Moves = { "upsert", "create-once", "update-only", "reference", "detect" };

        /// <summary>The manifest built into this assembly (the repo's config/manifest.json).</summary>
        public static Manifest LoadEmbedded()
        {
            using (var s = typeof(Manifest).Assembly.GetManifestResourceStream("CcAlm.Core.manifest.json"))
            {
                if (s == null) throw new InvalidOperationException("The built-in manifest is missing from CcAlm.Core.");
                using (var r = new StreamReader(s)) return Parse(r.ReadToEnd());
            }
        }

        public static Manifest Load(string path) => Parse(File.ReadAllText(path));

        public static Manifest Parse(string json)
        {
            var m = JsonConvert.DeserializeObject<Manifest>(json);
            if (m?.Tables == null || m.Tables.Count == 0) throw new InvalidDataException("Manifest has no tables array.");
            if (m.Version == null || !m.Version.StartsWith("2.", StringComparison.Ordinal))
                throw new InvalidDataException($"Manifest version {m.Version} is not supported. This engine reads version 2 manifests.");
            m.Tables = m.Tables.OrderBy(t => t.Order).ToList();
            foreach (var t in m.Tables)
            {
                if (string.IsNullOrEmpty(t.LogicalName)) throw new InvalidDataException($"Manifest table missing logicalName (order {t.Order}).");
                if (!Moves.Contains(t.Move)) throw new InvalidDataException($"Manifest table {t.LogicalName} has move '{t.Move}'; expected one of {string.Join(", ", Moves)}.");
                if (t.MatchKeys == null || t.MatchKeys.Count == 0) throw new InvalidDataException($"Manifest table {t.LogicalName} has no matchKeys.");
            }
            return m;
        }

        public ManifestTable Table(string logicalName) => Tables.FirstOrDefault(t => t.LogicalName == logicalName);

        public string StageLabel(int stage)
        {
            if (stage == 99) return "Link records written earlier";
            return Stages.FirstOrDefault(s => s.Stage == stage)?.Label ?? $"Stage {stage}";
        }
    }

    public sealed class StageInfo
    {
        [JsonProperty("stage")] public int Stage { get; set; }
        [JsonProperty("label")] public string Label { get; set; }
        [JsonProperty("description")] public string Description { get; set; }
    }

    public sealed class DetectRule
    {
        [JsonProperty("logicalName")] public string LogicalName { get; set; }
        [JsonProperty("signal")] public string Signal { get; set; }
        [JsonProperty("type")] public string Type { get; set; }
        [JsonProperty("message")] public string Message { get; set; }
    }

    public sealed class TextReference
    {
        /// <summary>A column name, or a prefix ending in * (msdyn_notificationtemplate_*).</summary>
        [JsonProperty("columns")] public string Columns { get; set; }
        [JsonProperty("target")] public string Target { get; set; }
        [JsonProperty("targetKey")] public string TargetKey { get; set; }
        [JsonProperty("label")] public string Label { get; set; }
    }

    public sealed class ManifestTable
    {
        [JsonProperty("order")] public int Order { get; set; }
        [JsonProperty("stage")] public int Stage { get; set; }
        [JsonProperty("logicalName")] public string LogicalName { get; set; }
        [JsonProperty("item")] public string Item { get; set; }
        [JsonProperty("move")] public string Move { get; set; }
        [JsonProperty("label")] public string Label { get; set; }
        [JsonProperty("group")] public string Group { get; set; }
        /// <summary>Web API style: a lookup is written _column_value.</summary>
        [JsonProperty("matchKeys")] public List<string> MatchKeys { get; set; } = new List<string>();
        [JsonProperty("exclude")] public List<string> Exclude { get; set; } = new List<string>();
        [JsonProperty("stripColumns")] public List<string> StripColumns { get; set; } = new List<string>();
        [JsonProperty("tieBreaker")] public string TieBreaker { get; set; }
        [JsonProperty("textReferences")] public List<TextReference> TextReferences { get; set; } = new List<TextReference>();
        [JsonProperty("guidBearingColumns")] public List<string> GuidBearingColumns { get; set; } = new List<string>();
        [JsonProperty("displayTemplate")] public string DisplayTemplate { get; set; }
        [JsonProperty("displayColumn")] public string DisplayColumn { get; set; }
        [JsonProperty("personalFilterColumn")] public string PersonalFilterColumn { get; set; }
        [JsonProperty("async")] public bool Async { get; set; }
        [JsonProperty("doubleWrite")] public bool DoubleWrite { get; set; }
        [JsonProperty("notes")] public string Notes { get; set; }

        public string DisplayLabel => string.IsNullOrEmpty(Label) ? LogicalName : Label;
        public string ItemLabel => string.IsNullOrEmpty(Item) ? DisplayLabel.ToLowerInvariant() : Item;
        public bool IsReadOnly => Move == "reference" || Move == "detect";
    }
}
