using System;
using System.Collections.Generic;
using System.Linq;
using CcAlm.Core.Model;

namespace CcAlm.Core.Engine
{
    public static class RecordStatus
    {
        public const string MissingInTarget = "MissingInTarget";
        public const string ExtraInTarget = "ExtraInTarget";
        public const string Changed = "Changed";
        public const string Equal = "Equal";
        public const string Ambiguous = "Ambiguous";

        public static bool IsMovable(string status) => status == MissingInTarget || status == Changed;
    }

    public sealed class FieldDiff
    {
        public string Name { get; set; }
        public string Label { get; set; }
        /// <summary>value, lookup or definition.</summary>
        public string Kind { get; set; }
        public string Source { get; set; }
        public string Target { get; set; }
    }

    public sealed class DependencyRef
    {
        public string Table { get; set; }
        public string MatchKey { get; set; }
        public string Label { get; set; }
        public string Via { get; set; }
        public bool Deferred { get; set; }
        /// <summary>lookup, name (a template named by unique name) or embedded (a GUID in a definition).</summary>
        public string Kind { get; set; }
        /// <summary>
        /// The parent the record is matched under (a routing step's routing configuration), as
        /// opposed to something it merely points at (the queue it routes to). Where it sits.
        /// </summary>
        public bool Owner { get; set; }
        public string Ref => $"{Table}|{MatchKey}";
    }

    public sealed class RecordDiff
    {
        public string Table { get; set; }
        public string MatchKey { get; set; }
        public string Status { get; set; }
        public string DisplayName { get; set; }
        public string Context { get; set; }
        public List<FieldDiff> Fields { get; } = new List<FieldDiff>();
        public List<DependencyRef> DependsOn { get; } = new List<DependencyRef>();
        public string Note { get; set; }
        public string Ref => $"{Table}|{MatchKey}";
        public string FullName => string.IsNullOrEmpty(Context) ? DisplayName : $"{Context} › {DisplayName}";
        public bool IsMovable => RecordStatus.IsMovable(Status);
    }

    public sealed class TableDiff
    {
        public string Table { get; set; }
        public string Label { get; set; }
        public string Group { get; set; }
        public int Stage { get; set; }
        public List<RecordDiff> Records { get; } = new List<RecordDiff>();
    }

    public sealed class DetectFinding
    {
        public string Type { get; set; }
        public string Table { get; set; }
        public string Label { get; set; }
        public string Record { get; set; }
        public string Message { get; set; }
    }

    public sealed class Notice
    {
        public string Severity { get; set; }
        public string Table { get; set; }
        public string Message { get; set; }
    }

    public sealed class DiffSummary
    {
        public int MissingInTarget { get; set; }
        public int ExtraInTarget { get; set; }
        public int Changed { get; set; }
        public int Equal { get; set; }
        public int Ambiguous { get; set; }
    }

    /// <summary>What a compare read from one environment, kept so a run need not read it again.</summary>
    public sealed class EnvReads
    {
        public string Url { get; set; }
        public DateTime ReadAt { get; set; }
        public Dictionary<string, TableSchema> Schemas { get; } = new Dictionary<string, TableSchema>();
        public Dictionary<string, List<Record>> Records { get; } = new Dictionary<string, List<Record>>();
    }

    /// <summary>The result of a compare, with what plan and run need to work from it.</summary>
    public sealed class DiffModel
    {
        public string DiffId { get; set; }
        public string SourceName { get; set; }
        public string TargetName { get; set; }
        public DateTime Generated { get; set; }
        public DiffSummary Summary { get; set; }
        public List<TableDiff> Tables { get; } = new List<TableDiff>();
        public List<DetectFinding> DetectOnly { get; } = new List<DetectFinding>();
        public List<Notice> Notices { get; } = new List<Notice>();

        // Context for plan, run and the check afterwards.
        public Manifest Manifest { get; set; }
        public Dictionary<string, TablePlan> TablePlans { get; set; }
        public EnvData Source { get; set; }
        public EnvData Target { get; set; }
        public Maps Maps { get; set; }
        public EnvReads SourceReads { get; set; }
        public EnvReads TargetReads { get; set; }

        public IEnumerable<RecordDiff> AllRecords => Tables.SelectMany(t => t.Records);

        Dictionary<string, RecordDiff> _byRef;
        public RecordDiff Find(string reference)
        {
            if (_byRef == null) _byRef = AllRecords.GroupBy(r => r.Ref).ToDictionary(g => g.Key, g => g.First());
            return reference != null && _byRef.TryGetValue(reference, out var r) ? r : null;
        }
    }
}
