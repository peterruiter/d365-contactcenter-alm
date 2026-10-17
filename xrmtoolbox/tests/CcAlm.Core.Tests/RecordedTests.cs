using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using CcAlm.Core.Engine;
using Newtonsoft.Json.Linq;
using Xunit;
using Xunit.Abstractions;

namespace CcAlm.Core.Tests
{
    /// <summary>
    /// Replays every recording in tests/fixtures/recorded (scripts/record-fixture.ps1) through this
    /// engine. baseline.json is what the PowerShell engine found when it was recorded, so these tests
    /// hold the two engines to the same answers on real configuration. Recordings are never committed;
    /// without any these tests pass without checking anything.
    /// </summary>
    public class RecordedTests
    {
        readonly ITestOutputHelper _out;
        public RecordedTests(ITestOutputHelper output) { _out = output; }

        static IEnumerable<string> Fixtures()
        {
            var dir = Path.Combine(Scenario.RepoRoot, "tests", "fixtures", "recorded");
            return Directory.Exists(dir) ? Directory.GetDirectories(dir).Where(d => File.Exists(Path.Combine(d, "baseline.json"))) : Enumerable.Empty<string>();
        }

        static (FakeDataverse Source, FakeDataverse Target, JObject Baseline) Load(string dir)
        {
            var src = new FakeDataverse("Source", "https://source.recorded.example", FakeDataverse.LoadMetadata(Path.Combine(dir, "source.metadata.json")));
            src.LoadRecords(Path.Combine(dir, "source.records.json"));
            var tgt = new FakeDataverse("Target", "https://target.recorded.example", FakeDataverse.LoadMetadata(Path.Combine(dir, "target.metadata.json")));
            tgt.LoadRecords(Path.Combine(dir, "target.records.json"));
            return (src, tgt, JObject.Parse(File.ReadAllText(Path.Combine(dir, "baseline.json"))));
        }

        [Fact]
        public void Compares_and_plans_exactly_as_the_PowerShell_engine_did()
        {
            foreach (var dir in Fixtures())
            {
                var (src, tgt, baseline) = Load(dir);
                var session = new MigrationSession(src, tgt);
                var diff = session.Compare();
                _out.WriteLine($"{Path.GetFileName(dir)}: {diff.Summary.MissingInTarget} new, {diff.Summary.Changed} changed, {diff.Summary.ExtraInTarget} extra, {diff.Summary.Equal} same, {diff.Summary.Ambiguous} ambiguous");

                var b = baseline["summary"];
                Assert.Equal((int)b["missingInTarget"], diff.Summary.MissingInTarget);
                Assert.Equal((int)b["extraInTarget"], diff.Summary.ExtraInTarget);
                Assert.Equal((int)b["changed"], diff.Summary.Changed);
                Assert.Equal((int)b["equal"], diff.Summary.Equal);
                Assert.Equal((int)b["ambiguous"], diff.Summary.Ambiguous);
                foreach (var t in diff.Tables)
                {
                    var then = (JObject)baseline["byTable"]?[t.Table];
                    if (then == null) continue;
                    foreach (var p in then.Properties())
                        Assert.True((int)p.Value == t.Records.Count(r => r.Status == p.Name), $"{t.Table}: {p.Name} was {(int)p.Value}, now {t.Records.Count(r => r.Status == p.Name)}");
                }

                var plan = session.BuildPlan(null);
                Assert.Equal((int)baseline["plan"]["ready"], plan.Summary.Ready);
                Assert.Equal((int)baseline["plan"]["blocked"], plan.Summary.Blocked);
                Assert.DoesNotContain(plan.Operations.SelectMany(o => o.Blockers), x => x.Message.Contains("Needs a ,"));
            }
        }

        [Fact]
        public void Dry_run_apply_check_and_rollback_on_real_configuration()
        {
            foreach (var dir in Fixtures())
            {
                var (src, tgt, _) = Load(dir);
                var before = tgt.Copy("https://target-before.recorded.example");
                var session = new MigrationSession(src, tgt);
                session.Compare();
                var plan = session.BuildPlan(null);

                var dry = T.Run(session, plan, dry: true);
                Assert.Empty(tgt.Writes);
                Assert.Equal(0, dry.Summary.Failed);
                Assert.Equal(0, dry.Summary.Skipped);

                var run = T.Run(session, plan, dry: false);
                _out.WriteLine($"{Path.GetFileName(dir)}: {run.Summary.Created} created, {run.Summary.Updated} updated, {run.Summary.Linked} linked; check: {run.Verification.Matched} of {run.Verification.Checked} match");
                foreach (var d in run.Verification.Differences)
                    _out.WriteLine($"  differs: {d.TableLabel} '{d.FullName}' {d.Status}: {string.Join("; ", d.Fields.Select(f => $"{f.Label} {f.Source} | {f.Target} {f.Note}"))}");
                Assert.Equal(0, run.Summary.Failed);
                Assert.Equal(0, run.Summary.Skipped);
                Assert.All(run.Verification.Differences, d => { Assert.Equal("Changed", d.Status); Assert.All(d.Fields, f => Assert.NotNull(f.Note)); });

                var rb = session.Rollback(run.Snapshot);
                Assert.Empty(rb.Unresolved);
                var back = new MigrationSession(before, tgt).Compare();
                Assert.Equal(0, back.Summary.MissingInTarget + back.Summary.ExtraInTarget + back.Summary.Changed);
            }
        }
    }
}
