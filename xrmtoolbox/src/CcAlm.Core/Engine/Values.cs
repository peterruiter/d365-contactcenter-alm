using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text.RegularExpressions;
using CcAlm.Core.Model;

namespace CcAlm.Core.Engine
{
    /// <summary>Comparing and showing values the same way in every environment.</summary>
    public static class Values
    {
        /// <summary>A value as invariant text, so two environments compare on content.</summary>
        public static string Text(object v)
        {
            switch (v)
            {
                case null: return "";
                case string s: return s;
                case bool b: return b ? "True" : "False";
                case decimal d: return (d / 1.000000000000000000000000000000000m).ToString(CultureInfo.InvariantCulture);
                case double x: return x.ToString("R", CultureInfo.InvariantCulture);
                case float f: return f.ToString("R", CultureInfo.InvariantCulture);
                case DateTime t: return t.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ", CultureInfo.InvariantCulture);
                case DateTimeOffset o: return o.UtcDateTime.ToString("yyyy-MM-ddTHH:mm:ssZ", CultureInfo.InvariantCulture);
                case Guid g: return g.ToString();
                case LookupValue l: return l.Id.ToString();
                case IFormattable fm: return fm.ToString(null, CultureInfo.InvariantCulture);
                default: return v.ToString();
            }
        }

        /// <summary>Null and empty text are the same setting; everything else compares as invariant text.</summary>
        public static bool Same(object a, object b) => string.Equals(Text(a), Text(b), StringComparison.Ordinal);

        /// <summary>The value as Dataverse shows it (choice labels, Yes/No), falling back to the raw value.</summary>
        public static string Formatted(Record r, string column)
        {
            if (r == null) return null;
            if (r.Formatted.TryGetValue(column, out var f) && f != null) return f;
            var v = r.Get(column);
            if (v == null) return null;
            if (v is bool b) return b ? "Yes" : "No";
            if (v is LookupValue l) return l.Name ?? l.Id.ToString();
            return Text(v);
        }

        /// <summary>"_msdyn_workstream_id_value" (Web API style, as the manifest writes lookups) → "msdyn_workstream_id".</summary>
        public static string Bare(string column)
        {
            if (column == null) return null;
            var m = Regex.Match(column, "^_(.+)_value$");
            return m.Success ? m.Groups[1].Value : column;
        }

        public static bool IsLookupKey(string column) => column != null && Regex.IsMatch(column, "^_.+_value$");
    }

    /// <summary>GUIDs inside text (a ruleset definition naming the queues it routes to).</summary>
    public static class References
    {
        static readonly Regex GuidPattern = new Regex("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}", RegexOptions.Compiled);

        public static IEnumerable<string> Guids(string text) =>
            string.IsNullOrEmpty(text) ? Enumerable.Empty<string>() : GuidPattern.Matches(text).Cast<Match>().Select(m => m.Value.ToLowerInvariant()).Distinct();

        /// <summary>Replaces every GUID the function knows (case-insensitively); null keeps the GUID.</summary>
        public static string Replace(string text, Func<string, string> replace) =>
            string.IsNullOrEmpty(text) ? text : GuidPattern.Replace(text, m => replace(m.Value.ToLowerInvariant()) ?? m.Value);

        /// <summary>Each embedded GUID as {entity:key}, so two environments' definitions compare on content.</summary>
        public static (string Text, List<string> Refs) Normalise(string definition, Dictionary<string, RecordRef> guidToRef)
        {
            var refs = new List<string>();
            var text = Replace(definition, g =>
            {
                if (!guidToRef.TryGetValue(g, out var r)) return null;
                refs.Add($"{r.Entity}|{r.Key}");
                return "{" + r.Entity + ":" + r.Key + "}";
            });
            return (text, refs.Distinct().ToList());
        }

        /// <summary>Source GUIDs → what they point at → that record's GUID in the target; unmapped ones reported.</summary>
        public static (string Text, List<RecordRef> Unmapped) ToTarget(string definition, Dictionary<string, RecordRef> sourceGuidToRef, Dictionary<string, Guid> targetKeyToGuid)
        {
            var unmapped = new List<RecordRef>();
            var text = Replace(definition, g =>
            {
                if (!sourceGuidToRef.TryGetValue(g, out var r)) return null;
                if (targetKeyToGuid.TryGetValue($"{r.Entity}|{r.Key}", out var t)) return t.ToString();
                unmapped.Add(r);
                return null;
            });
            return (text, unmapped);
        }
    }

    /// <summary>What a GUID points at, independent of environment: a table and a natural key.</summary>
    public sealed class RecordRef
    {
        public RecordRef(string entity, string key) { Entity = entity; Key = key; }
        public string Entity { get; }
        public string Key { get; }
        public string Ref => $"{Entity}|{Key}";
    }
}
