using System;
using System.Collections.Generic;
using System.Collections.Specialized;
using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Threading;
using System.Windows.Forms;
using CcAlm.Core.Engine;
using McTools.Xrm.Connection;
using Microsoft.Xrm.Sdk;
using XrmToolBox.Extensibility;
using Label = System.Windows.Forms.Label;

namespace CcAlm.XrmToolBox
{
    /// <summary>
    /// The tool: the XrmToolBox connection is the source, a second connection the target. Review what
    /// differs - by structure, so every record sits under the workstream or channel it belongs to -
    /// tick what to move (a record brings everything under it), check the plan, dry-run, apply with a
    /// check afterwards, and roll back.
    /// </summary>
    public sealed class MainControl : MultipleConnectionsPluginControlBase
    {
        static readonly Color Blue = ColorTranslator.FromHtml("#0070AD");
        static readonly Color Ink = ColorTranslator.FromHtml("#121A38");
        static readonly Color Muted = ColorTranslator.FromHtml("#5C6370");
        static readonly Color Red = ColorTranslator.FromHtml("#B3261E");
        static readonly Color Green = ColorTranslator.FromHtml("#1E7B34");
        static readonly Color Amber = ColorTranslator.FromHtml("#8A5A00");

        static readonly (string Status, string Label, Color Color)[] Statuses =
        {
            (RecordStatus.MissingInTarget, "New", Blue),
            (RecordStatus.Changed, "Changed", Amber),
            (RecordStatus.Ambiguous, "Ambiguous", Red),
            (RecordStatus.ExtraInTarget, "Only in target", Muted),
            (RecordStatus.Equal, "Same", Muted),
        };

        ConnectionDetail _targetDetail;
        IOrganizationService _targetService;
        MigrationSession _session;
        DiffModel _diff;
        Hierarchy _hier;
        Selection _selection;
        Plan _plan;
        string _dryRunPlanId;
        string _sourceUrl;
        RunResult _lastRun;
        bool _syncingChecks;
        bool _testing;
        readonly ToolTip _tips = new ToolTip();

        string TargetName => _targetDetail?.ConnectionName ?? _session?.Target.Name ?? "the target";

        // --- For tests/CcAlm.UiCheck, which drives the control without XrmToolBox connections ----------
        internal void UseSessionForTesting(MigrationSession session)
        {
            _testing = true;
            _session = session;
            _lblSource.Text = "Source: " + session.Source.Name;
            _sourceUrl = session.Source.Url;
            _lblTarget.Text = "Target: " + session.Target.Name;
            UpdateButtons();
        }
        internal void CompareForTesting() => Compare();
        internal void PlanForTesting() => BuildPlan();
        internal void DryRunForTesting() => Run(dry: true);
        internal void ShowTabForTesting(int index) => _tabs.SelectedIndex = index;
        internal void ShowViewForTesting(string view) { _view.SelectedIndex = _view.Items.IndexOf(view); }
        internal void SourceConnectionForTesting(string name, string url) => SourceChanged(null, name, url);
        internal string TreeSummaryForTesting()
        {
            var lines = new List<string>
            {
                $"top-level nodes: {_tree.Nodes.Count}, all nodes: {_tree.GetNodeCount(true)}, records shown: {ShownRecords().Count}",
                $"tree: visible={_tree.Visible} size={_tree.Size} handle={_tree.IsHandleCreated} top={(_tree.TopNode == null ? "(none)" : _tree.TopNode.Text)}",
            };
            foreach (TreeNode g in _tree.Nodes)
            {
                lines.Add($"  [{(g.IsVisible ? "visible" : "hidden ")}] {g.Text}  ({g.Nodes.Count} under it)");
                foreach (TreeNode c in g.Nodes) lines.Add($"      [{(c.IsVisible ? "visible" : "hidden ")}] {c.Text}");
            }
            return string.Join(Environment.NewLine, lines);
        }
        internal void SelectFirstRecordForTesting(string name)
        {
            var node = AllRecordNodes().FirstOrDefault(n => ((RecordDiff)n.Tag).DisplayName == name);
            if (node != null) _tree.SelectedNode = node;
        }

        // Toolbar
        ToolStripLabel _lblSource, _lblTarget;
        ToolStripButton _btnTarget, _btnCompare, _btnPlan, _btnDry, _btnApply, _btnRollback, _btnRuns;
        ToolStripLabel _status;
        SplitContainer _split;
        TabControl _tabs;
        TabPage _tabReview, _tabPlan, _tabRun;
        // Review
        ComboBox _view;
        TextBox _search;
        readonly Dictionary<string, CheckBox> _statusFilters = new Dictionary<string, CheckBox>();
        CheckBox _selectAll, _includeDeps;
        Label _selectionCount, _hint;
        TreeView _tree;
        // Which nodes the person has open, kept across rebuilds; the counts a container shows; and
        // what the last plan check blocked, so the tree says where the blocked records sit.
        readonly HashSet<string> _expanded = new HashSet<string>();
        bool _expansionSeeded, _applyingExpansion;
        readonly Dictionary<TreeNode, string> _nodeText = new Dictionary<TreeNode, string>();
        readonly Dictionary<string, Rollup> _rollups = new Dictionary<string, Rollup>();
        readonly HashSet<string> _blocked = new HashSet<string>();
        Label _detailTitle, _detailStatus;
        LinkLabel _detailOwner;
        Label _headNeeds, _headUsedBy, _headUnder;
        ListView _fields, _needs, _usedBy, _under;
        TextBox _notices;
        // Plan
        Label _planSummary;
        ListView _planList;
        Button _btnAddMissing;
        // Run
        Label _runTitle, _runCurrent;
        Button _btnDryRunHere;
        ProgressBar _runProgress;
        ListView _runList;
        TextBox _checkText;
        Button _btnRollbackRun, _btnOpenRuns;

        public MainControl()
        {
            BuildUi();
            UpdateButtons();
        }

        static string RunsDir => Path.Combine(Paths.SettingsPath, "ContactCenterALM", "runs");

        // --- Connections -----------------------------------------------------------------------------

        public override void UpdateConnection(IOrganizationService newService, ConnectionDetail detail, string actionName, object parameter)
        {
            base.UpdateConnection(newService, detail, actionName, parameter);
            // The target is chosen through this method as well. The base keeps it out of Service and
            // ConnectionDetail and raises ConnectionDetailsUpdated for it, which is where it belongs;
            // here it would overwrite the source.
            if (actionName == "AdditionalOrganization") return;
            SourceChanged(newService, detail?.ConnectionName, UrlOf(detail));
        }

        /// <summary>
        /// A source environment. XrmToolBox calls UpdateConnection again for the same environment -
        /// when its metadata cache has loaded, when it has refreshed the connection - so only a
        /// different environment throws the compare away. Resetting on every call emptied the tree
        /// and locked the buttons seconds after a compare, with the selection count still on screen.
        /// </summary>
        void SourceChanged(IOrganizationService service, string name, string url)
        {
            var changed = !string.Equals(url?.TrimEnd('/'), _sourceUrl?.TrimEnd('/'), StringComparison.OrdinalIgnoreCase);
            _sourceUrl = url;
            if (changed) ResetSession();
            // The same environment through a new connection (a reconnect, or impersonating someone):
            // what the compare read stays good, but everything from here on goes through the new one.
            else if (service != null) (_session?.Source as SdkDataverse)?.UseConnection(service);
            _lblSource.Text = "Source: " + (name ?? "not connected");
            UpdateButtons();
        }

        protected override void ConnectionDetailsUpdated(NotifyCollectionChangedEventArgs e)
        {
            if (e.Action == NotifyCollectionChangedAction.Add && e.NewItems?.Count > 0)
            {
                var detail = (ConnectionDetail)e.NewItems[e.NewItems.Count - 1];
                // One target at a time: a newly chosen one replaces the previous.
                foreach (var old in AdditionalConnectionDetails.Where(c => c != detail).ToList()) RemoveAdditionalOrganization(old);
                _targetDetail = detail;
                _targetService = detail.GetCrmServiceClient();
            }
            else if (e.Action == NotifyCollectionChangedAction.Remove && e.OldItems != null && e.OldItems.Contains(_targetDetail))
            {
                _targetDetail = null;
                _targetService = null;
            }
            ResetSession();
            _lblTarget.Text = "Target: " + (_targetDetail?.ConnectionName ?? "none");
            UpdateButtons();
        }

        /// <summary>
        /// Back to before the compare. Everything it put on screen goes with it: a cleared tree next
        /// to "147 of 147 selected" reads as a tool that lost its mind.
        /// </summary>
        void ResetSession()
        {
            _session = null; _diff = null; _hier = null; _selection = null; _plan = null; _dryRunPlanId = null;
            _tree?.Nodes.Clear();
            _nodeText.Clear(); _rollups.Clear(); _blocked.Clear();
            _expanded.Clear(); _expansionSeeded = false;
            _planList?.Items.Clear();
            if (_selectAll != null) { _selectAll.CheckState = CheckState.Unchecked; _selectAll.Text = "Select all"; }
            if (_selectionCount != null) _selectionCount.Text = "";
            if (_planSummary != null) { _planSummary.Text = "Select what to move on the Review tab, then Check the plan."; _planSummary.ForeColor = Muted; }
            if (_notices != null) _notices.Text = "";
            if (_fields != null) ShowDetails(null);
            UpdateButtons();
        }

        static string UrlOf(ConnectionDetail d) => d?.WebApplicationUrl ?? d?.OriginalUrl ?? d?.ConnectionName;

        MigrationSession Session()
        {
            if (_session == null && !_testing)
                _session = new MigrationSession(
                    new SdkDataverse(Service, ConnectionDetail?.ConnectionName ?? "Source", UrlOf(ConnectionDetail)),
                    new SdkDataverse(_targetService, _targetDetail?.ConnectionName ?? "Target", UrlOf(_targetDetail)));
            return _session;
        }

        bool Ready() => _testing || (Service != null && _targetService != null);

        /// <summary>What the Plan check and Run tabs say when there is nothing in them yet.</summary>
        void ShowWhatIsNext()
        {
            if (_planSummary == null || _runTitle == null) return;
            var next = _diff == null ? "Compare two environments first: the Compare button above reads both."
                : _selection == null || _selection.Selected.Count == 0 ? "Nothing is ticked. Tick what to move on the Review tab."
                : null;
            if (_plan == null) { _planSummary.Text = next ?? "Opening this tab checks the plan."; _planSummary.ForeColor = Muted; }
            if (_lastRun != null) return;
            var ready = _plan?.Summary.Ready ?? 0;
            _runTitle.Text = next ?? (ready > 0
                ? $"{ready} record{(ready == 1 ? "" : "s")} ready to write. A dry run goes through every write without writing anything; Apply unlocks after it."
                : _plan == null ? "Check the plan first: open the Plan check tab." : "Nothing in the plan can be written yet. The Plan check tab says why.");
            _runTitle.ForeColor = Ink;
        }

        void UpdateButtons()
        {
            if (_btnCompare == null) return;
            var ready = Ready();
            var sameOrg = ready && !_testing && string.Equals(UrlOf(ConnectionDetail)?.TrimEnd('/'), UrlOf(_targetDetail)?.TrimEnd('/'), StringComparison.OrdinalIgnoreCase);
            _btnCompare.Enabled = ready && !sameOrg;
            _btnCompare.ToolTipText = sameOrg ? "Source and target are the same environment." : "Read both environments and show what differs.";
            _btnPlan.Enabled = _diff != null && _selection?.Selected.Count > 0;
            _btnDry.Enabled = _plan != null && _plan.Summary.Ready > 0;
            _btnApply.Enabled = _plan != null && _plan.Summary.Ready > 0 && _dryRunPlanId == _plan.PlanId;
            _btnApply.ToolTipText = _btnApply.Enabled ? $"Write the plan to {_targetDetail?.ConnectionName}." : "Apply unlocks after a dry run of this plan.";
            _btnRollback.Enabled = ready;
            if (_btnRollbackRun != null) _btnRollbackRun.Enabled = _lastRun?.Snapshot != null && !_lastRun.IsDryRun;
            if (_btnDryRunHere != null) _btnDryRunHere.Enabled = _btnDry.Enabled;
            ShowWhatIsNext();
        }

        // --- Compare -------------------------------------------------------------------------------

        void Compare()
        {
            if (!Ready()) return;
            if (!_testing) _session = null;
            var session = Session();
            WorkAsync(new WorkAsyncInfo
            {
                Message = "Reading both environments",
                Work = (worker, args) => args.Result = session.Compare(msg => worker.ReportProgress(0, msg)),
                ProgressChanged = e => SetWorkingMessage(e.UserState as string),
                PostWorkCallBack = args =>
                {
                    if (args.Error != null) { ShowError(args.Error, "The compare did not finish"); return; }
                    _diff = (DiffModel)args.Result;
                    _hier = Hierarchy.Of(_diff);
                    _rollups.Clear();
                    _expanded.Clear(); _expansionSeeded = false;
                    _selection = new Selection(_diff);
                    _selection.SelectAll();
                    _plan = null; _dryRunPlanId = null; _blocked.Clear();
                    ShowNotices();
                    RebuildTree();
                    _tabs.SelectedTab = _tabReview;
                    var s = _diff.Summary;
                    Notify($"{s.MissingInTarget} new, {s.Changed} changed, {s.ExtraInTarget} only in {TargetName}, {s.Equal} the same{(s.Ambiguous > 0 ? $", {s.Ambiguous} ambiguous" : "")}.", null);
                    UpdateButtons();
                },
            });
        }

        void ShowNotices()
        {
            var lines = new List<string>();
            foreach (var n in _diff.Notices) lines.Add("• " + n.Message);
            if (_diff.DetectOnly.Count > 0)
            {
                lines.Add("");
                lines.Add("Set up by hand in the target (these cannot move as data):");
                foreach (var d in _diff.DetectOnly) lines.Add($"• {d.Label} '{d.Record}': {d.Message}");
            }
            _notices.Text = string.Join(Environment.NewLine, lines);
        }

        // --- Review tree ---------------------------------------------------------------------------

        /// <summary>What a container node says about everything under it: how much, and how much moves.</summary>
        sealed class Rollup
        {
            public int Under;
            public List<string> Movable = new List<string>();
        }

        /// <summary>The structure view is the default: every record under the one it belongs to.</summary>
        bool ByStructure => _view == null || _view.SelectedIndex == 0;

        (string Status, string Label, Color Color) StatusOf(RecordDiff r) => Statuses.First(x => x.Status == r.Status);

        string TableLabel(string table) => _diff.TablePlans.TryGetValue(table, out var p) ? p.Table.DisplayLabel : table;

        /// <summary>What one record of the table is called ("workstream"), for naming a single record.</summary>
        string ItemLabel(string table)
        {
            if (!_diff.TablePlans.TryGetValue(table, out var p)) return table;
            // A link has no useful name of its own; the relationship's label says what it is.
            return p.Table.Move == "associate" ? p.Table.DisplayLabel : p.Table.ItemLabel;
        }

        static string Capitalised(string text) =>
            string.IsNullOrEmpty(text) ? text : char.ToUpperInvariant(text[0]) + text.Substring(1);

        string GroupOf(string table) =>
            _diff.TablePlans.TryGetValue(table, out var p) && !string.IsNullOrEmpty(p.Table.Group) ? p.Table.Group : "Other";

        /// <summary>Does the record pass the status filters and the search box?</summary>
        bool Matches(RecordDiff r)
        {
            if (!_statusFilters.TryGetValue(r.Status, out var cb) || !cb.Checked) return false;
            var q = (_search.Text ?? "").Trim();
            return q.Length == 0
                || r.FullName.IndexOf(q, StringComparison.OrdinalIgnoreCase) >= 0
                || TableLabel(r.Table).IndexOf(q, StringComparison.OrdinalIgnoreCase) >= 0;
        }

        IEnumerable<RecordDiff> Shown(TableDiff t) => t.Records.Where(Matches).OrderBy(r => r.FullName, StringComparer.CurrentCultureIgnoreCase);

        Rollup RollupOf(string reference)
        {
            if (_rollups.TryGetValue(reference, out var cached)) return cached;
            var roll = new Rollup();
            foreach (var x in _hier.Descendants(reference))
            {
                roll.Under++;
                if (_diff.Find(x)?.IsMovable == true) roll.Movable.Add(x);
            }
            return _rollups[reference] = roll;
        }

        void RebuildTree()
        {
            if (_diff == null) return;
            _tree.BeginUpdate();
            _tree.Nodes.Clear();
            _nodeText.Clear();
            if (ByStructure) BuildStructureNodes(); else BuildTableNodes();
            if (!_expansionSeeded) { SeedExpansion(_tree.Nodes, 0); _expansionSeeded = true; }
            _applyingExpansion = true;
            ApplyExpansion(_tree.Nodes);
            _applyingExpansion = false;
            if (_tree.Nodes.Count > 0) _tree.Nodes[0].EnsureVisible();
            _tree.EndUpdate();
            SyncChecks();
        }

        /// <summary>Group, table, record: the plain list per table.</summary>
        void BuildTableNodes()
        {
            foreach (var group in _diff.Tables.GroupBy(t => GroupOf(t.Table)).OrderBy(g => g.Min(t => t.Stage)))
            {
                var gNode = new TreeNode(group.Key) { Tag = "group", Name = "g:" + group.Key, NodeFont = new Font(_tree.Font, FontStyle.Bold) };
                foreach (var t in group)
                {
                    var rows = Shown(t).ToList();
                    if (rows.Count == 0) continue;
                    var tNode = new TreeNode($"{t.Label} ({rows.Count})") { Tag = t, Name = "t:" + t.Table };
                    foreach (var r in rows)
                    {
                        var st = StatusOf(r);
                        tNode.Nodes.Add(new TreeNode($"{r.FullName}   [{st.Label}]")
                        { Tag = r, Name = "t:" + t.Table + "/" + r.Ref, ForeColor = r.IsMovable ? Ink : Muted, ToolTipText = st.Label + UsedWhereText(r) });
                    }
                    gNode.Nodes.Add(tNode);
                }
                if (gNode.Nodes.Count > 0) _tree.Nodes.Add(gNode);
            }
        }

        /// <summary>
        /// Every record under the one it belongs to: a workstream, its routing configuration, that
        /// configuration's steps, and under each step what it uses - the ruleset it runs, the queue it
        /// routes to - so what a record includes, and what includes it, is on screen without clicking.
        /// </summary>
        void BuildStructureNodes()
        {
            // A record shows when it passes the filters, and so does every record above it: a
            // workstream that is the same in both environments stays visible to hold its new steps.
            var visible = new HashSet<string>();
            foreach (var r in _diff.AllRecords)
            {
                if (!Matches(r)) continue;
                for (var x = r.Ref; x != null; x = _hier.OwnerOf(x)) if (!visible.Add(x)) break;
            }

            var groupStage = new Dictionary<string, int>();
            foreach (var t in _diff.Tables)
            {
                var g = GroupOf(t.Table);
                if (!groupStage.TryGetValue(g, out var stage) || t.Stage < stage) groupStage[g] = t.Stage;
            }

            var roots = _hier.Roots.Where(visible.Contains).Select(x => _diff.Find(x)).Where(r => r != null).ToList();
            foreach (var group in roots.GroupBy(r => GroupOf(r.Table))
                                       .OrderBy(g => groupStage.TryGetValue(g.Key, out var stage) ? stage : int.MaxValue)
                                       .ThenBy(g => g.Key, StringComparer.CurrentCultureIgnoreCase))
            {
                var gNode = new TreeNode { Tag = "group", Name = "g:" + group.Key, NodeFont = new Font(_tree.Font, FontStyle.Bold) };
                foreach (var r in group) gNode.Nodes.Add(StructureNode(r, visible, gNode.Name, new HashSet<string>()));
                gNode.Text = $"{group.Key} ({gNode.Nodes.Count})";
                _tree.Nodes.Add(gNode);
            }
        }

        TreeNode StructureNode(RecordDiff r, HashSet<string> visible, string parentKey, HashSet<string> above)
        {
            var key = parentKey + "/" + r.Ref;
            var node = new TreeNode { Tag = r, Name = key };
            var branch = new HashSet<string>(above) { r.Ref };
            foreach (var childRef in _hier.ChildrenOf(r.Ref))
            {
                var child = _diff.Find(childRef);
                if (child == null || !visible.Contains(childRef) || branch.Contains(childRef)) continue;
                node.Nodes.Add(StructureNode(child, visible, key, branch));
            }
            // What it uses, where it uses it. A leaf: the record itself sits elsewhere in the tree.
            foreach (var use in _hier.UsesOf(r.Ref))
            {
                var used = _diff.Find(use.Ref);
                if (used == null || !Matches(used)) continue;
                var st = StatusOf(used);
                node.Nodes.Add(new TreeNode($"uses {used.FullName} — {ItemLabel(used.Table)}   [{st.Label}]")
                {
                    Tag = used,
                    Name = key + "/uses:" + use.Ref,
                    ForeColor = Muted,
                    ToolTipText = $"{Capitalised(ItemLabel(used.Table))} · {st.Label}{Environment.NewLine}Used here through {use.Via}."
                                  + (use.Deferred ? " The link is set in the final pass of the run." : "")
                                  + UsedWhereText(used),
                });
            }
            SetStructureText(node, r);
            return node;
        }

        void SetStructureText(TreeNode node, RecordDiff r)
        {
            var st = StatusOf(r);
            // At the top of the tree a record needs the parent its name came from; below it, that
            // parent is the node above it.
            var name = _hier.OwnerOf(r.Ref) == null ? r.FullName : r.DisplayName;
            var text = $"{name} — {ItemLabel(r.Table)}   [{st.Label}]";
            var places = _hier.UsedBy(r.Ref).Select(u => u.Ref).Distinct().Count();
            if (places > 1) text += $" · used in {places} places";
            _nodeText[node] = text;
            node.Text = text;
            node.ForeColor = r.IsMovable ? Ink : Muted;
            node.ToolTipText = $"{Capitalised(ItemLabel(r.Table))} · {st.Label}" + (r.Note != null ? " · " + r.Note : "") + UsedWhereText(r);
        }

        string UsedWhereText(RecordDiff r)
        {
            var by = _hier.UsedBy(r.Ref).Select(u => _diff.Find(u.Ref)).Where(x => x != null).Select(x => x.FullName).Distinct().ToList();
            if (by.Count == 0) return "";
            var first = by.Take(6).Select(x => "• " + x);
            var more = by.Count > 6 ? $"{Environment.NewLine}• and {by.Count - 6} more" : "";
            return $"{Environment.NewLine}Used by:{Environment.NewLine}{string.Join(Environment.NewLine, first)}{more}";
        }

        void SeedExpansion(TreeNodeCollection nodes, int depth)
        {
            foreach (TreeNode n in nodes)
            {
                // The table view opens everything, as it always did. The structure view opens the
                // groups and what stands on its own, so the first screen is the workstreams and
                // channels, not every step of every one of them.
                if (n.Nodes.Count > 0 && depth < (ByStructure ? 2 : 3)) _expanded.Add(n.Name);
                SeedExpansion(n.Nodes, depth + 1);
            }
        }

        void ApplyExpansion(TreeNodeCollection nodes)
        {
            foreach (TreeNode n in nodes)
            {
                if (n.Nodes.Count == 0) continue;
                if (_expanded.Contains(n.Name)) n.Expand();
                ApplyExpansion(n.Nodes);
            }
        }

        IEnumerable<TreeNode> RecordNodes(TreeNode root)
        {
            foreach (TreeNode n in root.Nodes)
            {
                if (n.Tag is RecordDiff) yield return n;
                foreach (var c in RecordNodes(n)) yield return c;
            }
        }

        IEnumerable<TreeNode> AllRecordNodes() => _tree.Nodes.Cast<TreeNode>().SelectMany(RecordNodes);

        /// <summary>Every record on screen, each one once however often it is shown.</summary>
        List<RecordDiff> ShownRecords()
        {
            var seen = new HashSet<string>();
            return AllRecordNodes().Select(n => (RecordDiff)n.Tag).Where(r => seen.Add(r.Ref)).ToList();
        }

        void SyncChecks()
        {
            if (_selection == null) return;
            _syncingChecks = true;
            _tree.BeginUpdate();
            foreach (TreeNode n in _tree.Nodes) SyncNode(n);
            _tree.EndUpdate();
            var shown = ShownRecords().Where(r => r.IsMovable).ToList();
            var selectedShown = shown.Count(r => _selection.Selected.Contains(r.Ref));
            _selectAll.CheckState = shown.Count == 0 || selectedShown == 0 ? CheckState.Unchecked : selectedShown == shown.Count ? CheckState.Checked : CheckState.Indeterminate;
            _selectAll.Text = shown.Count == _diff.AllRecords.Count(r => r.IsMovable) ? $"Select all {shown.Count} records" : $"Select all {shown.Count} records shown";
            _selectionCount.Text = $"{_selection.Selected.Count} of {_diff.AllRecords.Count(r => r.IsMovable)} selected";
            _syncingChecks = false;
            UpdateButtons();
        }

        /// <summary>
        /// The ticks and the counts a container shows, down the whole tree: how many records sit under
        /// it, how many of those are ticked, and how many the last plan check blocked.
        /// </summary>
        (int Movable, int Ticked) SyncNode(TreeNode node)
        {
            int movable = 0, ticked = 0;
            if (node.Tag is RecordDiff self && self.IsMovable)
            {
                movable++;
                if (_selection.Selected.Contains(self.Ref)) ticked++;
            }
            foreach (TreeNode child in node.Nodes)
            {
                var counts = SyncNode(child);
                movable += counts.Movable;
                ticked += counts.Ticked;
            }

            if (node.Tag is RecordDiff r)
            {
                // From the structure, not from the nodes: a record used in two places is shown twice
                // and must not be counted twice.
                var roll = RollupOf(r.Ref);
                var tickedUnder = roll.Movable.Count(x => _selection.Selected.Contains(x));
                node.Checked = r.IsMovable
                    ? _selection.Selected.Contains(r.Ref)
                    : roll.Movable.Count > 0 && tickedUnder == roll.Movable.Count;
                if (_nodeText.TryGetValue(node, out var text))
                {
                    if (roll.Under > 0) text += $" · {roll.Under} under it, {tickedUnder} of {roll.Movable.Count} ticked";
                    if (_blocked.Count > 0)
                    {
                        var blocked = (_blocked.Contains(r.Ref) ? 1 : 0) + _hier.Descendants(r.Ref).Count(_blocked.Contains);
                        if (blocked > 0) text += $" · {blocked} blocked";
                    }
                    if (node.Text != text) node.Text = text;
                }
            }
            else node.Checked = movable > 0 && ticked == movable;
            return (movable, ticked);
        }

        void OnTreeCheck(object sender, TreeViewEventArgs e)
        {
            if (_syncingChecks || _selection == null || e.Action == TreeViewAction.Unknown) return;
            // Ticking a record ticks that record and Selection brings the rest. Ticking anything else -
            // a group, a table, a record that cannot move itself - ticks the records under it.
            var nodes = e.Node.Tag is RecordDiff self && self.IsMovable ? new[] { e.Node } : RecordNodes(e.Node).ToArray();
            var refs = nodes.Select(n => (RecordDiff)n.Tag).Where(r => r.IsMovable).Select(r => r.Ref).Distinct().ToList();
            if (refs.Count > 0)
            {
                var before = _selection.Selected.Count;
                _selection.Set(refs, e.Node.Checked);
                var brought = _selection.Selected.Count - before - (e.Node.Checked ? refs.Count : 0);
                if (e.Node.Tag is RecordDiff && e.Node.Checked && brought > 0)
                    Notify($"Selected with everything under it and what that uses: {brought} more record{(brought == 1 ? "" : "s")}.", null);
            }
            _plan = null; _dryRunPlanId = null; _blocked.Clear();
            SyncChecks();
            ShowDetails(_tree.SelectedNode?.Tag as RecordDiff);
        }

        void OnSelectAll(object sender, EventArgs e)
        {
            if (_syncingChecks || _selection == null) return;
            var shown = ShownRecords().Where(r => r.IsMovable).Select(r => r.Ref).ToList();
            var on = _selectAll.CheckState != CheckState.Unchecked;
            if (_selectAll.CheckState == CheckState.Indeterminate) { on = true; }
            _selection.Set(shown, on);
            _plan = null; _dryRunPlanId = null; _blocked.Clear();
            SyncChecks();
        }

        /// <summary>Puts a record on screen where it sits in the tree, and shows its details.</summary>
        void SelectRecord(string reference)
        {
            if (reference == null || _diff == null) return;
            var node = AllRecordNodes().FirstOrDefault(n => ((RecordDiff)n.Tag).Ref == reference);
            if (node == null) return;
            _tree.SelectedNode = node;
            node.EnsureVisible();
            _tree.Focus();
        }

        // --- Details -------------------------------------------------------------------------------

        void ShowDetails(RecordDiff r)
        {
            _fields.Items.Clear(); _needs.Items.Clear(); _usedBy.Items.Clear(); _under.Items.Clear();
            if (r == null || _diff == null)
            {
                _detailTitle.Text = "Select a record";
                _detailStatus.Text = "";
                _detailOwner.Visible = false;
                _headNeeds.Text = "What it needs";
                _headUsedBy.Text = "Where it is used";
                _headUnder.Text = "Everything under it";
                return;
            }
            var st = StatusOf(r);
            _detailTitle.Text = r.FullName;
            _detailStatus.Text = $"{Capitalised(ItemLabel(r.Table))} · {st.Label}" + (r.Note != null ? " · " + r.Note : "");
            _detailStatus.ForeColor = st.Color;

            // Where it sits: the records it is inside, outermost first, and a click goes up to them.
            var path = _hier.PathTo(r.Ref);
            if (path.Count > 0)
            {
                var names = path.Select(x => _diff.Find(x)?.DisplayName ?? x);
                _detailOwner.Text = "In " + string.Join(" › ", names);
                _detailOwner.Tag = path[path.Count - 1];
                _tips.SetToolTip(_detailOwner, "Go to " + (_diff.Find(path[path.Count - 1])?.FullName ?? "it"));
                _detailOwner.Visible = true;
            }
            else
            {
                _detailOwner.Text = "";
                _detailOwner.Tag = null;
                _detailOwner.Visible = false;
            }

            foreach (var f in r.Fields) _fields.Items.Add(new ListViewItem(new[] { f.Label, f.Source ?? "(empty)", f.Kind == "definition" ? "" : f.Target ?? "(empty)" }));
            if (r.Fields.Count == 0) _fields.Items.Add(new ListViewItem(new[] { r.Status == RecordStatus.MissingInTarget ? "New in the target" : "No differences", "", "" }) { ForeColor = Muted });

            foreach (var d in r.DependsOn)
            {
                var inTarget = _diff.Maps.TargetKeyToGuid.ContainsKey(d.Ref);
                var dep = _diff.Find(d.Ref);
                var state = inTarget ? "in the target" : dep?.Status == RecordStatus.MissingInTarget ? (_selection.Selected.Contains(d.Ref) ? "new · selected" : "new · not selected") : "missing";
                if (d.Deferred) state += " · linked at the end";
                if (d.Owner) state += " · it is under this one";
                _needs.Items.Add(new ListViewItem(new[] { d.Label, d.Via, state })
                { ForeColor = state.StartsWith("missing") || state.Contains("not selected") ? Red : Ink, Tag = dep != null ? d.Ref : null });
            }
            if (r.DependsOn.Count == 0) _needs.Items.Add(new ListViewItem(new[] { "It needs nothing else", "", "" }) { ForeColor = Muted });

            // The other direction: what would notice if this record were not moved.
            foreach (var use in _hier.UsedBy(r.Ref))
            {
                var by = _diff.Find(use.Ref);
                if (by == null) continue;
                var selected = _selection.Selected.Contains(use.Ref);
                _usedBy.Items.Add(new ListViewItem(new[] { by.FullName, TableLabel(by.Table), use.Via + (selected ? " · selected" : "") }) { Tag = use.Ref });
            }
            if (_usedBy.Items.Count == 0) _usedBy.Items.Add(new ListViewItem(new[] { "Nothing else points at it", "", "" }) { ForeColor = Muted });

            foreach (var refUnder in _hier.Descendants(r.Ref))
            {
                var u = _diff.Find(refUnder);
                if (u == null) continue;
                _under.Items.Add(new ListViewItem(new[] { u.FullName, TableLabel(u.Table), StatusOf(u).Label + (_selection.Selected.Contains(refUnder) ? " · selected" : "") }) { Tag = refUnder });
            }
            if (_under.Items.Count == 0) _under.Items.Add(new ListViewItem(new[] { "Nothing sits under it", "", "" }) { ForeColor = Muted });

            _headNeeds.Text = $"What it needs ({r.DependsOn.Count})";
            _headUsedBy.Text = $"Where it is used ({_hier.UsedBy(r.Ref).Select(u => u.Ref).Distinct().Count()})";
            var roll = RollupOf(r.Ref);
            _headUnder.Text = roll.Under == 0 ? "Everything under it" : $"Everything under it ({roll.Under}, {roll.Movable.Count} can move)";
        }

        /// <summary>A double-click in one of the three lists goes to that record in the tree.</summary>
        void GoToListRecord(ListView list)
        {
            if (list.SelectedItems.Count > 0) SelectRecord(list.SelectedItems[0].Tag as string);
        }

        // --- Plan ----------------------------------------------------------------------------------

        /// <summary>
        /// Opening a tab does what that tab is for. The plan check reads nothing from Dataverse - it
        /// works from what the compare read - so there is no reason to make someone press a button in
        /// the toolbar first and stare at an empty list until they find it.
        /// </summary>
        void OnTabOpened()
        {
            if (_tabs.SelectedTab == _tabPlan && _plan == null) BuildPlan(show: false);
            // The Run tab needs a plan before a dry run can be offered; build it, stay here.
            else if (_tabs.SelectedTab == _tabRun && _plan == null && _lastRun == null) BuildPlan(show: false);
            UpdateButtons();
        }

        void BuildPlan(bool show = true)
        {
            if (_diff == null || _selection == null || _selection.Selected.Count == 0) return;
            _plan = Session().BuildPlan(_selection.Selected.ToList(), _includeDeps.Checked);
            _dryRunPlanId = null;
            _blocked.Clear();
            foreach (var o in _plan.Operations.Where(o => o.Status == "blocked")) _blocked.Add(o.Ref);
            ShowPlan();
            RebuildTree();   // the counts per workstream now say where the blocked records sit
            if (show) _tabs.SelectedTab = _tabPlan;
            UpdateButtons();
        }

        void ShowPlan()
        {
            var s = _plan.Summary;
            _planSummary.Text = $"{s.Total} records: {s.Creates} new, {s.Updates} changed, {s.Ready} ready, {s.Blocked} blocked" +
                                (s.AutoIncluded > 0 ? $", {s.AutoIncluded} added because they are needed" : "") + (s.Links > 0 ? $", {s.Links} links set at the end" : "") + ".";
            _planSummary.ForeColor = s.Blocked > 0 ? Red : Ink;
            _planList.BeginUpdate();
            _planList.Items.Clear(); _planList.Groups.Clear();
            foreach (var stage in _plan.Operations.GroupBy(o => o.Stage).OrderBy(g => g.Key))
            {
                var grp = new ListViewGroup($"{stage.Key}. {_diff.Manifest.StageLabel(stage.Key)}");
                _planList.Groups.Add(grp);
                foreach (var o in stage)
                {
                    var why = o.Status == "blocked" ? string.Join(" ", o.Blockers.Select(b => b.Message))
                        : string.Join("; ", o.Dependencies.Select(d => $"{d.Label}: {StateText(d.State)}").Concat(o.Warnings));
                    // Nothing is in the plan without a reason: for a record added because something
                    // else needs it, that reason comes first.
                    if (o.AutoIncluded && o.NeededBy.Count > 0)
                        why = $"Needed by {string.Join(", ", o.NeededBy)}." + (why.Length > 0 ? "  " + why : "");
                    var action = o.Op == "create" ? "Create" : o.Op == "update" ? "Update" : o.Op == "link" ? "Link" : "Keep";
                    _planList.Items.Add(new ListViewItem(new[] { o.Status == "blocked" ? "Blocked" : "Ready", action, o.TableLabel, o.FullName + (o.AutoIncluded ? "  (needed)" : ""), why }, grp)
                    { ForeColor = o.Status == "blocked" ? Red : Ink, Tag = o });
                }
            }
            _planList.EndUpdate();
            _btnAddMissing.Enabled = _plan.Operations.Any(o => o.Blockers.Any(b => b.FixRef != null));
        }

        static string StateText(string state) =>
            state == "inTarget" ? "in the target" : state == "createdEarlier" ? "created earlier in this run" : state == "linkedLater" ? "linked at the end" : "missing";

        void AddMissing()
        {
            var fixes = _plan.Operations.SelectMany(o => o.Blockers).Where(b => b.FixRef != null).Select(b => b.FixRef).Distinct().ToList();
            if (fixes.Count == 0) return;
            _selection.Set(fixes, true);
            SyncChecks();
            BuildPlan();
        }

        // --- Run -----------------------------------------------------------------------------------

        sealed class WorkerProgress : IProgress<RunProgress>
        {
            readonly BackgroundWorker _w; readonly CancellationTokenSource _cts;
            public WorkerProgress(BackgroundWorker w, CancellationTokenSource cts) { _w = w; _cts = cts; }
            public void Report(RunProgress p)
            {
                if (_w.CancellationPending) _cts.Cancel();
                _w.ReportProgress(p.Total > 0 ? Math.Min(100, p.Done * 100 / p.Total) : 0, p);
            }
        }

        void Run(bool dry)
        {
            if (_plan == null) return;
            if (!dry)
            {
                var n = _plan.Summary.Ready;
                var msg = $"Write {n} record{(n == 1 ? "" : "s")} to {TargetName}?\n\n" +
                          "The target is read again first, so nothing is written from an old picture. Every record that is changed is snapshotted, so the run can be rolled back.\n\n" +
                          (_plan.Summary.Blocked > 0 ? $"{_plan.Summary.Blocked} blocked record(s) are not written.\n\n" : "") +
                          "This is not a Microsoft-supported path: test in a non-production environment first.";
                if (MessageBox.Show(this, msg, "Apply to " + TargetName, MessageBoxButtons.OKCancel, MessageBoxIcon.Warning) != DialogResult.OK) return;
            }
            var plan = _plan;
            var session = Session();
            _tabs.SelectedTab = _tabRun;
            _runList.Items.Clear(); _checkText.Text = "";
            _runTitle.Text = dry ? "Dry run in progress" : $"Applying to {TargetName}";
            _runProgress.Value = 0;
            _lastRun = null;
            UpdateButtons();

            WorkAsync(new WorkAsyncInfo
            {
                Message = dry ? "Dry run: going through every write" : "Writing to " + TargetName,
                IsCancelable = !dry,
                Work = (worker, args) =>
                {
                    using (var cts = new CancellationTokenSource())
                    {
                        string snapPath = null;
                        var result = session.Run(plan, dry, new WorkerProgress(worker, cts), cts.Token, snap =>
                        {
                            snapPath = snapPath ?? Path.Combine(RunsDir, $"snapshot-{snap.RunId}.json");
                            RunStore.Save(snapPath, snap);
                        });
                        RunStore.Save(Path.Combine(RunsDir, $"run-{result.RunId}.json"), result);
                        args.Result = result;
                    }
                },
                ProgressChanged = e =>
                {
                    var p = e.UserState as RunProgress;
                    if (p == null) return;
                    _runProgress.Value = Math.Max(0, Math.Min(100, e.ProgressPercentage));
                    if (p.Current != null) { _runCurrent.Text = p.Current; SetWorkingMessage(p.Current); }
                    if (p.Item != null) AddRunItem(p.Item);
                },
                PostWorkCallBack = args =>
                {
                    if (args.Error != null) { ShowError(args.Error, "The run did not finish"); _runTitle.Text = "The run did not finish"; return; }
                    _lastRun = (RunResult)args.Result;
                    if (dry && _lastRun.State != "Cancelled") _dryRunPlanId = plan.PlanId;
                    ShowRun(_lastRun);
                    UpdateButtons();
                },
            });
        }

        void AddRunItem(RunItem i)
        {
            var color = i.Outcome == Outcome.Failed || i.Outcome == Outcome.Blocked ? Red : i.Outcome == Outcome.Skipped ? Amber : Outcome.IsWrite(i.Outcome) ? Green : Ink;
            _runList.Items.Add(new ListViewItem(new[] { OutcomeText(i.Outcome), i.Stage == 99 ? "links" : i.Stage.ToString(), i.TableLabel, i.FullName, i.Message }) { ForeColor = color });
        }

        static string OutcomeText(string o)
        {
            switch (o)
            {
                case Outcome.Created: return "Created";
                case Outcome.Updated: return "Updated";
                case Outcome.Linked: return "Linked";
                case Outcome.Unchanged: return "Kept";
                case Outcome.WouldCreate: return "Would create";
                case Outcome.WouldUpdate: return "Would update";
                case Outcome.WouldLink: return "Would link";
                case Outcome.Skipped: return "Skipped";
                case Outcome.Blocked: return "Blocked";
                default: return "Failed";
            }
        }

        void ShowRun(RunResult run)
        {
            _runList.BeginUpdate();
            _runList.Items.Clear();
            foreach (var i in run.Items.OrderBy(x => x.Stage).ThenBy(x => x.Seq)) AddRunItem(i);
            _runList.EndUpdate();
            _runProgress.Value = 100;
            _runCurrent.Text = "";
            var s = run.Summary;
            var verb = run.IsDryRun ? "would be " : "";
            _runTitle.Text = (run.IsDryRun ? "Dry run finished" : run.State == "Cancelled" ? "Apply cancelled" : $"Applied to {run.Target}") +
                             $": {s.Created} {verb}created, {s.Updated} {verb}updated, {s.Linked} {(run.IsDryRun ? "links to set" : "linked")}, {s.Skipped + s.Blocked} not moved, {s.Failed} failed.";
            _runTitle.ForeColor = s.Failed > 0 ? Red : Ink;
            _checkText.Text = CheckText(run);
        }

        static string CheckText(RunResult run)
        {
            var nl = Environment.NewLine;
            if (run.IsDryRun) return "Nothing was written. This is exactly what applying the plan would do." + (run.Summary.Failed + run.Summary.Skipped > 0 ? nl + "Records with problems will not be written; fix them in the plan or apply the rest." : "");
            var v = run.Verification;
            if (v == null) return run.State == "Cancelled" ? "The run was cancelled. What it wrote stands and can be rolled back." : "";
            if (v.State == "Error") return v.Message + " The writes themselves stand.";
            var lines = new List<string>();
            lines.Add(v.State == "Verified"
                ? $"Checked: the target matches the source. All {v.Checked} records this run wrote were read back and are the same as in the source."
                : $"Checked: {v.Differences.Count} record(s) still differ. {v.Matched} of {v.Checked} written records are the same as in the source.");
            foreach (var d in v.Differences)
            {
                lines.Add($"• {d.TableLabel} '{d.FullName}': {d.Message}");
                foreach (var f in d.Fields) lines.Add($"    {f.Label}: source {f.Source ?? "(empty)"} · target {f.Target ?? "(empty)"}{(f.Note != null ? " — " + f.Note : "")}");
            }
            if (v.Added.Count > 0)
            {
                lines.Add("");
                lines.Add("Appeared in the target during the run, created by Dataverse on its own (not in the source):");
                foreach (var a in v.Added) lines.Add($"• {a.TableLabel}: {a.FullName}");
            }
            return string.Join(nl, lines);
        }

        // --- Rollback ------------------------------------------------------------------------------

        void RollbackFromFile()
        {
            Directory.CreateDirectory(RunsDir);
            using (var dlg = new OpenFileDialog { InitialDirectory = RunsDir, Filter = "Run snapshots (snapshot-*.json)|snapshot-*.json", Title = "Roll back a run" })
            {
                if (dlg.ShowDialog(this) != DialogResult.OK) return;
                Rollback(RunStore.Load<Snapshot>(dlg.FileName));
            }
        }

        void Rollback(Snapshot snapshot)
        {
            if (snapshot == null) return;
            var msg = $"Roll back run {snapshot.RunId} in {_targetDetail?.ConnectionName}?\n\n" +
                      $"{snapshot.Updated.Count} changed record(s) are set back to how they were, and {snapshot.Created.Count} created record(s) are deleted.";
            if (MessageBox.Show(this, msg, "Roll back", MessageBoxButtons.OKCancel, MessageBoxIcon.Warning) != DialogResult.OK) return;
            var session = Session();
            WorkAsync(new WorkAsyncInfo
            {
                Message = "Rolling back",
                Work = (worker, args) => args.Result = session.Rollback(snapshot, new Progress<string>(m => worker.ReportProgress(0, m))),
                ProgressChanged = e => SetWorkingMessage(e.UserState as string),
                PostWorkCallBack = args =>
                {
                    if (args.Error != null) { ShowError(args.Error, "The rollback did not finish"); return; }
                    var r = (RollbackResult)args.Result;
                    var text = $"Rollback finished: {r.Restored} record(s) restored, {r.Deleted} created record(s) deleted.";
                    if (r.Unresolved.Count > 0) text += Environment.NewLine + string.Join(Environment.NewLine, r.Unresolved.Select(u => "• " + u));
                    _checkText.Text = text;
                    _tabs.SelectedTab = _tabRun;
                    MessageBox.Show(this, text, "Roll back", MessageBoxButtons.OK, r.Unresolved.Count > 0 ? MessageBoxIcon.Warning : MessageBoxIcon.Information);
                    ResetSession();
                },
            });
        }

        void Notify(string text, Uri link)
        {
            _status.Text = text;
            try { ShowInfoNotification(text, link); }
            catch (Exception) { /* not hosted in XrmToolBox's window: the status line has it */ }
        }

        void ShowError(Exception ex, string title) =>
            MessageBox.Show(this, ex.Message, title, MessageBoxButtons.OK, MessageBoxIcon.Error);

        // --- Layout --------------------------------------------------------------------------------

        bool _splitPlaced;
        protected override void OnLayout(LayoutEventArgs e)
        {
            base.OnLayout(e);
            if (_splitPlaced || _split == null || _split.Width < 320 + 360 + 10) return;
            _split.SplitterDistance = Math.Max(320, Math.Min(_split.Width - 360, (int)(_split.Width * 0.45)));
            _split.Panel1MinSize = 320;
            _split.Panel2MinSize = 360;
            _splitPlaced = true;
        }

        void BuildUi()
        {
            SuspendLayout();
            Font = new Font("Segoe UI", 9f);
            BackColor = Color.White;

            var bar = new ToolStrip { GripStyle = ToolStripGripStyle.Hidden, Padding = new Padding(6, 2, 6, 2), RenderMode = ToolStripRenderMode.System };
            _lblSource = new ToolStripLabel("Source: not connected") { ForeColor = Ink };
            _btnTarget = new ToolStripButton("Choose target…") { ToolTipText = "Connect the environment to move to." };
            _btnTarget.Click += (s, e) => AddAdditionalOrganization();
            _lblTarget = new ToolStripLabel("Target: none") { ForeColor = Ink };
            _btnCompare = new ToolStripButton("Compare") { Font = new Font(Font, FontStyle.Bold), ForeColor = Blue };
            _btnCompare.Click += (s, e) => ExecuteMethod(Compare);
            _btnPlan = new ToolStripButton("Check the plan") { ToolTipText = "Check every dependency of the selection before anything runs." };
            _btnPlan.Click += (s, e) => BuildPlan();
            _btnDry = new ToolStripButton("Dry run") { ToolTipText = "Go through every write without writing anything." };
            _btnDry.Click += (s, e) => Run(dry: true);
            _btnApply = new ToolStripButton("Apply") { ForeColor = Red };
            _btnApply.Click += (s, e) => Run(dry: false);
            _btnRollback = new ToolStripButton("Roll back a run…") { ToolTipText = "Undo an earlier apply from its snapshot." };
            _btnRollback.Click += (s, e) => RollbackFromFile();
            _btnRuns = new ToolStripButton("Runs folder") { ToolTipText = RunsDir };
            _btnRuns.Click += (s, e) => { Directory.CreateDirectory(RunsDir); Process.Start("explorer.exe", RunsDir); };
            _status = new ToolStripLabel("") { Alignment = ToolStripItemAlignment.Right, ForeColor = Muted };
            bar.Items.AddRange(new ToolStripItem[] { _lblSource, new ToolStripSeparator(), _btnTarget, _lblTarget, new ToolStripSeparator(), _btnCompare, new ToolStripSeparator(), _btnPlan, _btnDry, _btnApply, new ToolStripSeparator(), _btnRollback, _btnRuns, _status });

            _tabs = new TabControl { Dock = DockStyle.Fill };
            _tabReview = new TabPage("1. Review");
            _tabPlan = new TabPage("2. Plan check");
            _tabRun = new TabPage("3. Run");
            _tabs.TabPages.AddRange(new[] { _tabReview, _tabPlan, _tabRun });
            _tabs.SelectedIndexChanged += (s, e) => OnTabOpened();
            BuildReview();
            BuildPlanTab();
            BuildRunTab();

            Controls.Add(_tabs);
            Controls.Add(bar);
            ResumeLayout();
        }

        static ListView NewList(params (string Header, int Width)[] cols)
        {
            var lv = new ListView { View = View.Details, FullRowSelect = true, Dock = DockStyle.Fill, HeaderStyle = ColumnHeaderStyle.Nonclickable, BorderStyle = BorderStyle.FixedSingle };
            foreach (var c in cols) lv.Columns.Add(c.Header, c.Width);
            return lv;
        }

        static Label Heading(string text) => new Label { Text = text, Dock = DockStyle.Top, Height = 24, Font = new Font("Segoe UI Semibold", 9.5f), ForeColor = Ink, Padding = new Padding(0, 6, 0, 0) };

        void BuildReview()
        {
            // The splitter is placed once the tab has its real size (see OnLayout).
            // Minimum sizes too: setting them before the control has its width throws.
            var split = _split = new SplitContainer { Dock = DockStyle.Fill, FixedPanel = FixedPanel.None };
            _tabReview.Controls.Add(split);

            // Left: how to show them, filters, select all, the tree.
            var top = new FlowLayoutPanel { Dock = DockStyle.Top, Height = 64, Padding = new Padding(4), WrapContents = true };
            _view = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 132 };
            _view.Items.AddRange(new object[] { "By structure", "By table" });
            _view.SelectedIndex = 0;
            _view.SelectedIndexChanged += (s, e) => { _expanded.Clear(); _expansionSeeded = false; ShowHint(); RebuildTree(); };
            _tips.SetToolTip(_view, "By structure: every record under the workstream, channel or queue it belongs to.\r\nBy table: one list per table.");
            top.Controls.Add(new Label { Text = "Show:", AutoSize = true, Padding = new Padding(0, 6, 0, 0) });
            top.Controls.Add(_view);
            _search = new TextBox { Width = 180 };
            _search.TextChanged += (s, e) => RebuildTree();
            top.Controls.Add(new Label { Text = "Find:", AutoSize = true, Padding = new Padding(6, 6, 0, 0) });
            top.Controls.Add(_search);
            foreach (var st in Statuses)
            {
                var cb = new CheckBox { Text = st.Label, AutoSize = true, Checked = st.Status != RecordStatus.Equal, ForeColor = st.Color };
                cb.CheckedChanged += (s, e) => RebuildTree();
                _statusFilters[st.Status] = cb;
                top.Controls.Add(cb);
            }
            var selectRow = new Panel { Dock = DockStyle.Top, Height = 30, Padding = new Padding(6, 4, 6, 0), BackColor = ColorTranslator.FromHtml("#F8FAFC") };
            _selectAll = new CheckBox { Text = "Select all", AutoSize = true, ThreeState = false, Dock = DockStyle.Left };
            _selectAll.Click += OnSelectAll;
            _selectionCount = new Label { Text = "", AutoSize = true, Dock = DockStyle.Right, ForeColor = Muted, Padding = new Padding(0, 4, 0, 0) };
            selectRow.Controls.Add(_selectAll);
            selectRow.Controls.Add(_selectionCount);
            _tree = new TreeView { Dock = DockStyle.Fill, CheckBoxes = true, HideSelection = false, ShowNodeToolTips = true, BorderStyle = BorderStyle.None, FullRowSelect = true };
            _tree.AfterCheck += OnTreeCheck;
            _tree.AfterSelect += (s, e) => ShowDetails(e.Node.Tag as RecordDiff);
            _tree.AfterExpand += (s, e) => { if (!_applyingExpansion && e.Node.Name != null) _expanded.Add(e.Node.Name); };
            _tree.AfterCollapse += (s, e) => { if (!_applyingExpansion && e.Node.Name != null) _expanded.Remove(e.Node.Name); };
            _hint = new Label { Dock = DockStyle.Bottom, Height = 36, ForeColor = Muted, Padding = new Padding(6, 2, 6, 2) };
            ShowHint();
            _includeDeps = new CheckBox { Text = "Add the records they need to the plan", Checked = true, Dock = DockStyle.Bottom, Height = 24, Padding = new Padding(6, 0, 0, 0) };
            split.Panel1.Controls.Add(_tree);
            split.Panel1.Controls.Add(selectRow);
            split.Panel1.Controls.Add(top);
            split.Panel1.Controls.Add(_includeDeps);
            split.Panel1.Controls.Add(_hint);

            // Right: details.
            var right = new Panel { Dock = DockStyle.Fill, Padding = new Padding(8) };
            split.Panel2.Controls.Add(right);
            _detailTitle = new Label { Text = "Compare to see what differs", Dock = DockStyle.Top, Height = 28, Font = new Font("Segoe UI Semilight", 13f), ForeColor = Ink, AutoEllipsis = true };
            _detailOwner = new LinkLabel { Dock = DockStyle.Top, Height = 20, Visible = false, LinkColor = Blue, ActiveLinkColor = Blue, AutoEllipsis = true };
            _detailOwner.LinkClicked += (s, e) => SelectRecord(_detailOwner.Tag as string);
            _detailStatus = new Label { Dock = DockStyle.Top, Height = 22, ForeColor = Muted, AutoEllipsis = true };
            _fields = NewList(("Setting", 180), ("Source", 220), ("Target", 220));
            _needs = NewList(("Needs", 300), ("Through", 160), ("State", 180));
            _usedBy = NewList(("Used by", 340), ("Table", 160), ("Through", 160));
            _under = NewList(("Under it", 340), ("Table", 160), ("Status", 160));
            foreach (var list in new[] { _needs, _usedBy, _under })
            {
                var l = list;
                l.DoubleClick += (s, e) => GoToListRecord(l);
                _tips.SetToolTip(l, "Double-click a row to go to that record in the tree.");
            }
            _notices = new TextBox { Dock = DockStyle.Bottom, Height = 90, Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical, BorderStyle = BorderStyle.None, BackColor = ColorTranslator.FromHtml("#F8FAFC") };
            _headNeeds = Heading("What it needs");
            _headUsedBy = Heading("Where it is used");
            _headUnder = Heading("Everything under it");
            var grid = new TableLayoutPanel { Dock = DockStyle.Fill, RowCount = 8, ColumnCount = 1 };
            grid.RowStyles.Add(new RowStyle(SizeType.Absolute, 24)); grid.RowStyles.Add(new RowStyle(SizeType.Percent, 28));
            grid.RowStyles.Add(new RowStyle(SizeType.Absolute, 24)); grid.RowStyles.Add(new RowStyle(SizeType.Percent, 24));
            grid.RowStyles.Add(new RowStyle(SizeType.Absolute, 24)); grid.RowStyles.Add(new RowStyle(SizeType.Percent, 24));
            grid.RowStyles.Add(new RowStyle(SizeType.Absolute, 24)); grid.RowStyles.Add(new RowStyle(SizeType.Percent, 24));
            grid.Controls.Add(Heading("What differs"), 0, 0); grid.Controls.Add(_fields, 0, 1);
            grid.Controls.Add(_headNeeds, 0, 2); grid.Controls.Add(_needs, 0, 3);
            grid.Controls.Add(_headUsedBy, 0, 4); grid.Controls.Add(_usedBy, 0, 5);
            grid.Controls.Add(_headUnder, 0, 6); grid.Controls.Add(_under, 0, 7);
            right.Controls.Add(grid);
            right.Controls.Add(_notices);
            right.Controls.Add(_detailStatus);
            right.Controls.Add(_detailOwner);
            right.Controls.Add(_detailTitle);
        }

        void ShowHint() =>
            _hint.Text = ByStructure
                ? "Every record sits under the one it belongs to; a line marked \"uses\" is a record from elsewhere in the tree, shown where it is used. "
                  + "Ticking a record also ticks everything under it and what that uses."
                : "One list per table. Ticking a record also ticks everything under it and what that uses: a workstream brings its routing configuration, "
                  + "its steps, their rulesets and queues.";

        void BuildPlanTab()
        {
            var top = new Panel { Dock = DockStyle.Top, Height = 40, Padding = new Padding(8, 8, 8, 4) };
            _planSummary = new Label { Dock = DockStyle.Fill, Text = "Compare two environments first: the Compare button above reads both.", ForeColor = Muted };
            _btnAddMissing = new Button { Text = "Add what is missing", Dock = DockStyle.Right, Width = 160, Enabled = false };
            _btnAddMissing.Click += (s, e) => AddMissing();
            top.Controls.Add(_planSummary);
            top.Controls.Add(_btnAddMissing);
            _planList = NewList(("Status", 70), ("Action", 70), ("Table", 160), ("Record", 360), ("Why / what it needs", 600));
            _planList.ShowGroups = true;
            _tabPlan.Controls.Add(_planList);
            _tabPlan.Controls.Add(top);
        }

        void BuildRunTab()
        {
            var top = new Panel { Dock = DockStyle.Top, Height = 74, Padding = new Padding(8) };
            _runTitle = new Label { Dock = DockStyle.Top, Height = 24, Font = new Font("Segoe UI Semibold", 10f), ForeColor = Ink, Text = "Compare two environments first: the Compare button above reads both." };
            _runProgress = new ProgressBar { Dock = DockStyle.Top, Height = 14 };
            _runCurrent = new Label { Dock = DockStyle.Top, Height = 22, ForeColor = Muted };
            // The same dry run as in the toolbar, where someone looking at an empty run list is.
            _btnDryRunHere = new Button { Text = "Dry run", Dock = DockStyle.Top, Height = 28, Enabled = false, Font = new Font("Segoe UI Semibold", 9f) };
            _btnDryRunHere.Click += (s, e) => Run(dry: true);
            var dryRunHost = new Panel { Dock = DockStyle.Right, Width = 128, Padding = new Padding(8, 0, 0, 0) };
            dryRunHost.Controls.Add(_btnDryRunHere);
            top.Controls.Add(_runCurrent); top.Controls.Add(_runProgress); top.Controls.Add(_runTitle);
            top.Controls.Add(dryRunHost);

            var bottom = new Panel { Dock = DockStyle.Bottom, Height = 170, Padding = new Padding(8, 4, 8, 8) };
            _checkText = new TextBox { Dock = DockStyle.Fill, Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical, BorderStyle = BorderStyle.FixedSingle, BackColor = ColorTranslator.FromHtml("#F8FAFC") };
            var buttons = new FlowLayoutPanel { Dock = DockStyle.Right, Width = 180, FlowDirection = FlowDirection.TopDown };
            _btnRollbackRun = new Button { Text = "Roll back this run", Width = 168, Enabled = false };
            _btnRollbackRun.Click += (s, e) => Rollback(_lastRun?.Snapshot);
            _btnOpenRuns = new Button { Text = "Open runs folder", Width = 168 };
            _btnOpenRuns.Click += (s, e) => { Directory.CreateDirectory(RunsDir); Process.Start("explorer.exe", RunsDir); };
            buttons.Controls.Add(_btnRollbackRun); buttons.Controls.Add(_btnOpenRuns);
            bottom.Controls.Add(_checkText); bottom.Controls.Add(buttons);

            _runList = NewList(("Outcome", 100), ("Stage", 50), ("Table", 160), ("Record", 340), ("Message", 600));
            _tabRun.Controls.Add(_runList);
            _tabRun.Controls.Add(bottom);
            _tabRun.Controls.Add(top);
        }
    }
}
