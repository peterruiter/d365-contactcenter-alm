using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;
using CcAlm.Core.Model;
using Newtonsoft.Json;

namespace CcAlm.Core.Engine
{
    /// <summary>
    /// One source and one target, and the steps between them: compare, plan, dry run or apply with the
    /// check afterwards, roll back. Keeps what the compare read, so the plan and a dry run read nothing
    /// again and an apply re-reads only the target's records.
    /// </summary>
    public sealed class MigrationSession
    {
        public MigrationSession(IDataverse source, IDataverse target, Manifest manifest = null)
        {
            Source = source;
            Target = target;
            Manifest = manifest ?? Manifest.LoadEmbedded();
        }

        public IDataverse Source { get; }
        public IDataverse Target { get; }
        public Manifest Manifest { get; }
        public DiffModel Diff { get; private set; }

        /// <summary>How long a compare's reads of the source stay good enough for a run.</summary>
        public TimeSpan ReadsValidFor { get; set; } = TimeSpan.FromHours(1);

        /// <summary>How long to wait for Dataverse to provision a new workstream.</summary>
        public int ProvisioningTimeoutSeconds { get; set; } = 60;
        /// <summary>The run's clock; tests replace it so waits pass instantly.</summary>
        public Action<TimeSpan> Sleep { get; set; } = t => Thread.Sleep(t);
        public Func<DateTime> Now { get; set; } = () => DateTime.UtcNow;

        RunOptions Options(bool dry, IProgress<RunProgress> progress, CancellationToken cancel, Action<Snapshot> save) => new RunOptions
        {
            DryRun = dry, Progress = progress, Cancel = cancel, SaveSnapshot = save,
            ProvisioningTimeoutSeconds = ProvisioningTimeoutSeconds, Sleep = Sleep, Now = Now,
        };

        public DiffModel Compare(Action<string> progress = null)
        {
            Diff = Comparer.Compare(Manifest, Source, Target, progress: progress);
            return Diff;
        }

        public Plan BuildPlan(IEnumerable<string> selection, bool includeDependencies = true)
        {
            if (Diff == null) throw new InvalidOperationException("Compare first.");
            return Planner.Build(Diff, selection, includeDependencies);
        }

        /// <summary>
        /// Runs a plan. A dry run uses the compare it came from as is. An apply first reads the target
        /// again (the source and the metadata come from the compare) and plans the same selection
        /// against it, so it never writes from a stale picture; then it checks afterwards that every
        /// record it wrote now matches the source.
        /// </summary>
        public RunResult Run(Plan plan, bool dryRun, IProgress<RunProgress> progress = null, CancellationToken cancel = default, Action<Snapshot> saveSnapshot = null)
        {
            if (dryRun) return Runner.Run(plan, Target, Options(true, progress, cancel, null));

            var selection = plan.Operations.Select(o => o.Ref).ToList();
            var baseDiff = plan.Diff;
            var sourceReads = Fresh(baseDiff.SourceReads) ? baseDiff.SourceReads : null;
            progress?.Report(new RunProgress { Phase = "comparing", Current = "Reading the target again before writing" });
            var current = Comparer.Compare(Manifest, Source, Target, sourceReads, TargetSchemasOnly(baseDiff.TargetReads), s => progress?.Report(new RunProgress { Phase = "comparing", Current = s }));
            var extraBefore = Verification.ExtraRefs(current);
            var livePlan = Planner.Build(current, selection, includeDependencies: false);

            var result = Runner.Run(livePlan, Target, Options(false, progress, cancel, saveSnapshot));
            if (result.State == "Cancelled" || !result.Items.Any(i => Outcome.IsWrite(i.Outcome))) return result;

            progress?.Report(new RunProgress { Phase = "verifying", Current = "Checking the target against the source" });
            try
            {
                var after = Comparer.Compare(Manifest, Source, Target, current.SourceReads, TargetSchemasOnly(current.TargetReads));
                result.Verification = Verification.Check(after, result.Items, extraBefore);
                Diff = after;
            }
            catch (Exception ex)
            {
                result.Verification = new Verification { State = "Error", CheckedAt = DateTime.UtcNow, Message = "The check afterwards could not run: " + ex.Message };
            }
            return result;
        }

        public RollbackResult Rollback(Snapshot snapshot, IProgress<string> progress = null)
        {
            if (!string.Equals(snapshot.Environment?.TrimEnd('/'), Target.Url?.TrimEnd('/'), StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException($"This snapshot is of {snapshot.Environment}, not of {Target.Url}. Connect that environment as the target to roll it back.");
            var schemas = new Dictionary<string, TableSchema>();
            TableSchema SchemaOf(string t) => schemas.TryGetValue(t, out var s) ? s : schemas[t] = Target.GetTableSchema(t);
            return Engine.Rollback.Restore(snapshot, Target, SchemaOf, progress);
        }

        bool Fresh(EnvReads reads) => reads != null && DateTime.UtcNow - reads.ReadAt < ReadsValidFor;

        /// <summary>The target's metadata from a compare, without its records, so they are read again.</summary>
        static EnvReads TargetSchemasOnly(EnvReads reads)
        {
            if (reads == null) return null;
            var copy = new EnvReads { Url = reads.Url, ReadAt = DateTime.UtcNow };
            foreach (var kv in reads.Schemas) copy.Schemas[kv.Key] = kv.Value;
            return copy;
        }
    }

    /// <summary>Snapshots and run records as JSON files, for rollback and history.</summary>
    public static class RunStore
    {
        static readonly JsonSerializerSettings Settings = new JsonSerializerSettings
        {
            Formatting = Formatting.Indented,
            TypeNameHandling = TypeNameHandling.None,
            DateTimeZoneHandling = DateTimeZoneHandling.Utc,
        };

        public static void Save(string path, object value)
        {
            var dir = Path.GetDirectoryName(path);
            if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
            var tmp = path + ".tmp";
            File.WriteAllText(tmp, JsonConvert.SerializeObject(value, Settings));
            if (File.Exists(path)) File.Delete(path);
            File.Move(tmp, path);
        }

        public static T Load<T>(string path) => JsonConvert.DeserializeObject<T>(File.ReadAllText(path), Settings);
    }
}
