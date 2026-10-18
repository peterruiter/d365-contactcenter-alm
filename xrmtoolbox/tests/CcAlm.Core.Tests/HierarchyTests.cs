using System.Linq;
using CcAlm.Core.Engine;
using Xunit;

namespace CcAlm.Core.Tests
{
    /// <summary>
    /// Where the tool shows each record: under the one it belongs to, with what it merely points at
    /// listed as a use. The structure comes from the match keys, so it is the same structure the
    /// records are matched and named by.
    /// </summary>
    public class HierarchyTests
    {
        readonly Scenario _s = new Scenario();
        readonly DiffModel _diff;
        readonly Hierarchy _h;

        public HierarchyTests()
        {
            _diff = new MigrationSession(_s.Dev, _s.Test).Compare();
            _h = Hierarchy.Of(_diff);
        }

        RecordDiff Workstream => T.Row(_diff, "msdyn_liveworkstream", "Mortgage chat");
        RecordDiff Config => T.Row(_diff, "msdyn_routingconfiguration", "Contact center routing configuration", "Mortgage chat");
        RecordDiff Step => T.Row(_diff, "msdyn_routingconfigurationstep", "Route to queue", "Mortgage chat › Contact center routing configuration");
        RecordDiff Queue => T.Row(_diff, "queue", "Mortgage queue");
        RecordDiff Ruleset => T.Row(_diff, "msdyn_decisionruleset", "Mortgage route");

        string Name(string reference) => _diff.Find(reference)?.FullName;

        [Fact]
        public void A_step_sits_under_its_routing_configuration_under_its_workstream()
        {
            Assert.Equal(Config.Ref, _h.OwnerOf(Step.Ref));
            Assert.Equal(Workstream.Ref, _h.OwnerOf(Config.Ref));
            Assert.Equal(new[] { "Mortgage chat", "Mortgage chat › Contact center routing configuration" }, _h.PathTo(Step.Ref).Select(Name));
        }

        [Fact]
        public void A_workstream_stands_on_its_own_and_everything_of_it_is_under_it()
        {
            Assert.Null(_h.OwnerOf(Workstream.Ref));
            Assert.Contains(Workstream.Ref, _h.Roots);
            Assert.Contains(Config.Ref, _h.Descendants(Workstream.Ref));
            Assert.Contains(Step.Ref, _h.Descendants(Workstream.Ref));
        }

        [Fact]
        public void A_queue_a_step_routes_to_is_a_use_not_something_under_it()
        {
            Assert.DoesNotContain(Queue.Ref, _h.Descendants(Workstream.Ref));
            Assert.Null(_h.OwnerOf(Queue.Ref));
            // It is the workstream's default queue, and the ruleset's definition names it.
            Assert.Equal(
                new[] { "Mortgage chat", "Mortgage route" },
                _h.UsedBy(Queue.Ref).Select(u => Name(u.Ref)).Distinct().OrderBy(x => x));
            Assert.Contains(Queue.Ref, _h.UsesOf(Workstream.Ref).Select(u => u.Ref));
        }

        [Fact]
        public void A_step_uses_the_ruleset_it_runs()
        {
            var use = Assert.Single(_h.UsesOf(Step.Ref), u => u.Ref == Ruleset.Ref);
            Assert.Equal("Rule set", use.Via);
            Assert.Contains(Step.Ref, _h.UsedBy(Ruleset.Ref).Select(u => u.Ref));
        }

        [Fact]
        public void A_many_to_many_link_sits_under_the_end_written_first()
        {
            var link = T.Row(_diff, "msdyn_msdyn_cannedmessage_liveworkstream", "Greeting", "Mortgage chat");
            Assert.Equal(Workstream.Ref, _h.OwnerOf(link.Ref));
            // The quick reply itself is written later, so the link only points at it.
            var reply = T.Row(_diff, "msdyn_cannedmessage", "Greeting");
            Assert.Contains(reply.Ref, _h.UsesOf(link.Ref).Select(u => u.Ref));
            Assert.All(_h.UsesOf(link.Ref), u => Assert.True(u.Deferred));
        }

        [Fact]
        public void Every_record_has_exactly_one_place_in_the_tree()
        {
            var placed = _h.Roots.SelectMany(r => new[] { r }.Concat(_h.Descendants(r))).ToList();
            Assert.Equal(_diff.AllRecords.Select(r => r.Ref).OrderBy(x => x), placed.OrderBy(x => x));
        }

        [Fact]
        public void What_is_under_a_record_is_in_write_order()
        {
            var order = _diff.TablePlans.ToDictionary(kv => kv.Key, kv => kv.Value.Table.Order);
            foreach (var root in _h.Roots)
            {
                var children = _h.ChildrenOf(root).Select(c => order[_diff.Find(c).Table]).ToList();
                Assert.Equal(children.OrderBy(x => x), children);
            }
        }
    }
}
