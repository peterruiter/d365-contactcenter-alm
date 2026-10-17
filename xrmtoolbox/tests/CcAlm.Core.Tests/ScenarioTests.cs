using System;
using System.Collections.Generic;
using System.Linq;
using CcAlm.Core.Engine;
using CcAlm.Core.Model;
using Xunit;

namespace CcAlm.Core.Tests
{
    static class T
    {
        public static RecordDiff Row(DiffModel d, string table, string name, string context = null) =>
            d.AllRecords.Where(r => r.Table == table && r.DisplayName == name && (context == null || r.Context == context)).ToList() is var rows && rows.Count > 0 ? rows[0] : null;

        public static List<RecordDiff> Rows(DiffModel d, string table, string name) => d.AllRecords.Where(r => r.Table == table && r.DisplayName == name).ToList();

        public static PlanOperation Op(Plan p, string table, string name) => p.Operations.FirstOrDefault(o => o.Table == table && o.DisplayName == name);

        public static RunResult Run(MigrationSession s, Plan p, bool dry, List<Snapshot> snapshots = null)
        {
            // A virtual clock: provisioning waits pass instantly.
            var now = DateTime.UtcNow;
            s.Now = () => now;
            s.Sleep = t => now += t;
            return s.Run(p, dry, saveSnapshot: snap => snapshots?.Add(snap));
        }
    }

    public class CompareTests
    {
        readonly Scenario _s = new Scenario();
        readonly DiffModel _diff;
        public CompareTests() { _diff = new MigrationSession(_s.Dev, _s.Test).Compare(); }

        [Fact]
        public void Pairs_records_by_what_they_are_not_by_guid()
        {
            Assert.Equal(RecordStatus.Equal, T.Row(_diff, "msdyn_operatinghour", "Office hours").Status);
            Assert.Equal(RecordStatus.Equal, T.Row(_diff, "queue", "Billing queue").Status);
            Assert.Equal(RecordStatus.Equal, T.Row(_diff, "msdyn_sessiontemplate", "Chat session").Status);
        }

        [Fact]
        public void A_ruleset_pointing_at_the_same_records_under_other_guids_is_the_same()
            => Assert.Equal(RecordStatus.Equal, T.Row(_diff, "msdyn_decisionruleset", "Billing route").Status);

        [Fact]
        public void Lists_exactly_the_setting_that_changed()
        {
            var r = T.Row(_diff, "msdyn_liveworkstream", "Billing chat");
            Assert.Equal(RecordStatus.Changed, r.Status);
            var f = Assert.Single(r.Fields);
            Assert.Equal("Capacity", f.Label);
            Assert.Equal("2", f.Source);
            Assert.Equal("1", f.Target);
        }

        [Fact]
        public void Tells_duplicate_names_apart_with_the_tie_breaker()
            => Assert.Equal(new[] { RecordStatus.Equal, RecordStatus.MissingInTarget }, T.Rows(_diff, "msdyn_capacityprofile", "Chat capacity").Select(r => r.Status).OrderBy(x => x));

        [Fact]
        public void Never_pairs_records_it_cannot_tell_apart()
        {
            var vip = T.Row(_diff, "msdyn_octag", "VIP");
            Assert.Equal(RecordStatus.Ambiguous, vip.Status);
            Assert.Contains("2 records in the source", vip.Note);
        }

        [Fact]
        public void Reports_target_only_records_and_leaves_personal_queues_out()
        {
            Assert.Equal(RecordStatus.ExtraInTarget, T.Row(_diff, "msdyn_octag", "Old tag").Status);
            Assert.Null(T.Row(_diff, "queue", "<Peter>"));
        }

        [Fact]
        public void Finds_a_changed_step_under_an_unchanged_routing_configuration()
        {
            Assert.Equal(RecordStatus.Equal, T.Row(_diff, "msdyn_routingconfiguration", "Contact center routing configuration", "Billing chat").Status);
            var step = T.Row(_diff, "msdyn_routingconfigurationstep", "Route to queue", "Billing chat › Contact center routing configuration");
            Assert.Equal(RecordStatus.Changed, step.Status);
            Assert.Equal(new[] { "Rule set" }, step.Fields.Select(f => f.Label));
        }

        [Fact]
        public void Every_dependency_is_a_real_record()
        {
            var deps = _diff.AllRecords.SelectMany(r => r.DependsOn).ToList();
            Assert.NotEmpty(deps);
            Assert.All(deps, d => { Assert.False(string.IsNullOrEmpty(d.Table)); Assert.False(string.IsNullOrEmpty(d.MatchKey)); Assert.False(string.IsNullOrEmpty(d.Label)); });
            Assert.Empty(T.Row(_diff, "msdyn_cannedmessage", "Greeting").DependsOn);
        }

        [Fact]
        public void Flags_what_has_to_be_set_up_per_environment()
            => Assert.Equal(new[] { "channelAccount:Mortgage WhatsApp" }, _diff.DetectOnly.Select(d => $"{d.Type}:{d.Record}"));

        [Fact]
        public void Finds_the_many_to_many_links()
        {
            var links = _diff.Tables.Single(t => t.Table == "msdyn_msdyn_cannedmessage_liveworkstream");
            Assert.Equal("Quick replies on workstreams", links.Label);
            Assert.Equal(new[] { "Billing chat › Greeting MissingInTarget", "Mortgage chat › Greeting MissingInTarget" }, links.Records.Select(r => $"{r.FullName} {r.Status}").OrderBy(x => x));
            Assert.Equal(new[] { "Greeting › Escalated" }, _diff.Tables.Single(t => t.Table == "msdyn_msdyn_cannedmessage_msdyn_octag").Records.Select(r => r.FullName));
        }

        [Fact]
        public void Finds_nothing_to_move_between_an_environment_and_itself()
        {
            var self = new MigrationSession(_s.Dev, _s.Dev.Copy("https://contoso-dev-copy.crm4.dynamics.com")).Compare();
            Assert.Equal(0, self.Summary.MissingInTarget + self.Summary.Changed + self.Summary.ExtraInTarget);
        }
    }

    public class PlanTests
    {
        readonly Scenario _s = new Scenario();
        readonly MigrationSession _session;
        readonly DiffModel _diff;
        readonly Plan _plan;
        public PlanTests()
        {
            _session = new MigrationSession(_s.Dev, _s.Test);
            _diff = _session.Compare();
            _plan = _session.BuildPlan(null);
        }

        [Fact]
        public void Blocks_only_what_cannot_be_written_each_with_its_reason()
        {
            Assert.Equal(new[] { "GPT chat", "Mortgage WhatsApp" }, _plan.Operations.Where(o => o.Status == "blocked").Select(o => o.DisplayName).OrderBy(x => x));
            Assert.Equal(new[] { "managedMissing" }, T.Op(_plan, "msdyn_liveworkstream", "GPT chat").Blockers.Select(b => b.Code));
            Assert.Contains("external", T.Op(_plan, "msdyn_ocwhatsappchannelnumber", "Mortgage WhatsApp").Blockers.Select(b => b.Code));
        }

        [Fact]
        public void Plans_records_without_dependencies_as_ready()
        {
            var g = T.Op(_plan, "msdyn_cannedmessage", "Greeting");
            Assert.Equal("ready", g.Status);
            Assert.Empty(g.Dependencies);
        }

        [Fact]
        public void Never_changes_a_decision_contract_that_already_exists()
            => Assert.Equal("skip-existing", T.Op(_plan, "msdyn_decisioncontract", "Billing contract").Op);

        [Fact]
        public void Links_a_lookup_to_a_later_table_at_the_end()
            => Assert.Equal("linkedLater", T.Op(_plan, "msdyn_liveworkstream", "Mortgage chat").Dependencies.Single(d => d.Label == "queue 'Mortgage queue'").State);

        [Fact]
        public void Adds_everything_a_selected_record_needs()
        {
            var step = T.Row(_diff, "msdyn_routingconfigurationstep", "Route to queue", "Mortgage chat › Contact center routing configuration");
            var p = _session.BuildPlan(new[] { step.Ref });
            var names = p.Operations.Select(o => o.DisplayName).ToList();
            foreach (var n in new[] { "Route to queue", "Contact center routing configuration", "Mortgage chat", "Mortgage route", "Mortgage queue", "Mortgage contract", "Mortgages", "Mortgage session", "Mortgage notification" })
                Assert.Contains(n, names);
            Assert.Equal(0, p.Summary.Blocked);
        }

        [Fact]
        public void Offers_the_fix_when_a_needed_record_is_left_out()
        {
            var step = T.Row(_diff, "msdyn_routingconfigurationstep", "Route to queue", "Mortgage chat › Contact center routing configuration");
            var p = _session.BuildPlan(new[] { step.Ref }, includeDependencies: false);
            var b = p.Operations[0].Blockers.Where(x => x.Code == "missingDependency").ToList();
            Assert.NotEmpty(b);
            Assert.All(b, x => Assert.NotNull(x.FixRef));
        }

        [Fact]
        public void Plans_nothing_for_an_empty_selection()
        {
            Assert.Empty(_session.BuildPlan(new string[0]).Operations);
            Assert.Equal(_plan.Operations.Count, _session.BuildPlan(null).Operations.Count);
        }
    }

    public class SelectionTests
    {
        readonly DiffModel _diff = new MigrationSession(new Scenario().Dev, new Scenario().Test).Compare();

        [Fact]
        public void Ticking_a_workstream_ticks_its_routing_steps_rulesets_and_queues()
        {
            var sel = new Selection(_diff);
            sel.Toggle(T.Row(_diff, "msdyn_liveworkstream", "Mortgage chat").Ref);
            var names = sel.Selected.Select(r => _diff.Find(r).FullName).ToList();
            foreach (var n in new[] { "Mortgage chat", "Mortgage chat › Contact center routing configuration", "Mortgage chat › Contact center routing configuration › Route to queue",
                                      "Mortgage route", "Mortgage queue", "Mortgage chat › CustomerTier" })
                Assert.Contains(n, names);
            Assert.DoesNotContain("Billing chat", names);
            // Its quick-reply link and the quick reply come along.
            Assert.Contains("Mortgage chat › Greeting", names);
            Assert.Contains("Greeting", names);
        }

        [Fact]
        public void Unticking_keeps_what_another_ticked_record_still_needs()
        {
            var sel = new Selection(_diff);
            sel.SelectAll();
            var all = sel.Selected.Count;
            sel.Toggle(T.Row(_diff, "msdyn_liveworkstream", "Mortgage chat").Ref);
            Assert.DoesNotContain(T.Row(_diff, "msdyn_liveworkstream", "Mortgage chat").Ref, sel.Selected);
            Assert.DoesNotContain(T.Row(_diff, "msdyn_routingconfiguration", "Contact center routing configuration", "Mortgage chat").Ref, sel.Selected);
            Assert.Contains(T.Row(_diff, "msdyn_liveworkstream", "Billing chat").Ref, sel.Selected);
            Assert.True(sel.Selected.Count < all);
        }
    }

    public class RunTests
    {
        [Fact]
        public void A_dry_run_writes_nothing_and_fails_nothing()
        {
            var s = new Scenario();
            var session = new MigrationSession(s.Dev, s.Test);
            session.Compare();
            var plan = session.BuildPlan(null);
            var run = T.Run(session, plan, dry: true);
            Assert.Empty(s.Test.Writes);
            Assert.Equal(0, run.Summary.Failed);
            Assert.Equal(0, run.Summary.Skipped);
            Assert.Equal(plan.Operations.Count(o => o.Status == "ready" && o.Op == "create"), run.Summary.Created);
            Assert.Equal(6, run.Summary.Linked);   // 3 lookups set at the end, 3 quick-reply links
        }

        [Fact]
        public void A_dry_run_after_a_compare_reads_nothing_again()
        {
            var s = new Scenario();
            var session = new MigrationSession(s.Dev, s.Test);
            session.Compare();
            int before = s.Dev.MetadataReads + s.Dev.RecordReads + s.Test.MetadataReads + s.Test.RecordReads;
            T.Run(session, session.BuildPlan(null), dry: true);
            Assert.Equal(before, s.Dev.MetadataReads + s.Dev.RecordReads + s.Test.MetadataReads + s.Test.RecordReads);
        }

        [Fact]
        public void An_apply_re_reads_only_the_target_records()
        {
            var s = new Scenario();
            var session = new MigrationSession(s.Dev, s.Test);
            session.Compare();
            var plan = session.BuildPlan(null);
            int dev = s.Dev.MetadataReads + s.Dev.RecordReads, meta = s.Test.MetadataReads, recs = s.Test.RecordReads;
            T.Run(session, plan, dry: false);
            Assert.Equal(dev, s.Dev.MetadataReads + s.Dev.RecordReads);
            Assert.Equal(meta, s.Test.MetadataReads);
            Assert.True(s.Test.RecordReads > recs);
        }

        [Fact]
        public void An_apply_writes_every_ready_record_checks_it_and_rolls_back_exactly()
        {
            var s = new Scenario();
            var before = s.Test.Copy("https://contoso-test-before.crm4.dynamics.com");
            var session = new MigrationSession(s.Dev, s.Test);
            session.Compare();
            var snapshots = new List<Snapshot>();
            var run = T.Run(session, session.BuildPlan(null), dry: false, snapshots);

            Assert.Equal(0, run.Summary.Failed);
            Assert.Equal(0, run.Summary.Skipped);
            Assert.Equal(2, run.Summary.Blocked);
            Assert.Equal("Verified", run.Verification.State);
            Assert.Equal(run.Verification.Checked, run.Verification.Matched);
            Assert.Empty(run.Verification.Added);

            // GUIDs inside the ruleset now point at the target's records.
            var route = s.Test.Where("msdyn_decisionruleset", "msdyn_uniquename", "contoso_mortgage_route").Single();
            var queue = s.Test.Where("queue", "name", "Mortgage queue").Single();
            Assert.Contains(queue.Id.ToString(), (string)route.Get("msdyn_rulesetdefinition"));
            Assert.DoesNotContain(s.DevIds["mortgageQueue"].ToString(), (string)route.Get("msdyn_rulesetdefinition"));

            // The link to a later table was set in the final pass.
            var ws = s.Test.Where("msdyn_liveworkstream", "msdyn_name", "Mortgage chat").Single();
            Assert.Equal(queue.Id, ws.GetLookup("msdyn_defaultqueue").Id);

            // A ruleset's second write is an update without the unique name.
            var second = s.Test.Writes.Where(w => w.Table == "msdyn_decisionruleset" && w.Method == "Update").ToList();
            Assert.Single(second);
            Assert.False(second[0].Values.ContainsKey("msdyn_uniquename"));

            // The quick reply is on both workstreams and carries its tag.
            Assert.Equal(2, s.Test.Rows["msdyn_msdyn_cannedmessage_liveworkstream"].Count);
            Assert.Single(s.Test.Rows["msdyn_msdyn_cannedmessage_msdyn_octag"]);

            // Only the blocked records are left to move.
            var again = new MigrationSession(s.Dev, s.Test);
            again.Compare();
            Assert.Equal(new[] { "GPT chat", "Mortgage WhatsApp" }, again.BuildPlan(null).Operations.Where(o => o.Op != "skip-existing").Select(o => o.DisplayName).OrderBy(x => x));

            var rb = session.Rollback(run.Snapshot);
            Assert.Empty(rb.Unresolved);
            Assert.Equal(run.Summary.Created, rb.Deleted);
            var diff = new MigrationSession(before, s.Test).Compare();
            Assert.Equal(0, diff.Summary.MissingInTarget + diff.Summary.ExtraInTarget + diff.Summary.Changed);
        }

        [Fact]
        public void The_check_afterwards_lists_what_dataverse_added_and_rollback_removes_it()
        {
            var s = new Scenario(provisionRoutingContract: true);
            var session = new MigrationSession(s.Dev, s.Test);
            session.Compare();
            var run = T.Run(session, session.BuildPlan(null), dry: false);
            Assert.Contains(run.Verification.Added, a => a.Table == "msdyn_decisioncontract");
            Assert.Contains(run.Snapshot.Created, c => c.Label.StartsWith("Routing contract Dataverse created", StringComparison.Ordinal));
            var contracts = s.Test.Rows["msdyn_decisioncontract"].Count;
            var rb = session.Rollback(run.Snapshot);
            Assert.Empty(rb.Unresolved);
            Assert.True(s.Test.Rows["msdyn_decisioncontract"].Count < contracts);
        }

        [Fact]
        public void The_check_afterwards_reports_a_write_that_dataverse_changed()
        {
            var s = new Scenario();
            s.Test.OnWrite = (method, table, r) => { if (table == "queue" && method == "Create") r.Values["msdyn_priority"] = 99L; };
            var session = new MigrationSession(s.Dev, s.Test);
            session.Compare();
            var v = T.Run(session, session.BuildPlan(null), dry: false).Verification;
            Assert.Equal("Differences", v.State);
            var d = Assert.Single(v.Differences);
            Assert.Equal("Mortgage queue", d.DisplayName);
            Assert.Equal("Priority", d.Fields[0].Label);
            Assert.Equal("2|99", $"{d.Fields[0].Source}|{d.Fields[0].Target}");
        }

        [Fact]
        public void A_failed_write_holds_back_only_what_depends_on_it()
        {
            var s = new Scenario();
            s.Test.FailWhen = (method, table, values) => table == "queue" && method == "Create" ? "A queue with this name already exists." : null;
            var session = new MigrationSession(s.Dev, s.Test);
            session.Compare();
            var run = T.Run(session, session.BuildPlan(null), dry: false);
            var failed = Assert.Single(run.Items, i => i.Outcome == Outcome.Failed);
            Assert.Equal("Mortgage queue", failed.DisplayName);
            Assert.Equal("A queue with this name already exists.", failed.Message);
            Assert.Equal(Outcome.Skipped, run.Items.Single(i => i.DisplayName == "Mortgage route").Outcome);
            Assert.Equal(Outcome.Created, run.Items.Single(i => i.Table == "msdyn_cannedmessage" && i.DisplayName == "Greeting").Outcome);
            var d = Assert.Single(run.Verification.Differences);
            Assert.Equal("Mortgage chat", d.DisplayName);
        }
    }
}
