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
    /// differs, tick what to move (a record brings everything under it), check the plan, dry-run,
    /// apply with a check afterwards, and roll back.
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
        Selection _selection;
        Plan _plan;
        string _dryRunPlanId;
        RunResult _lastRun;
        bool _syncingChecks;
        bool _testing;

        string TargetName => _targetDetail?.ConnectionName ?? _session?.Target.Name ?? "the target";

        // --- For tests/CcAlm.UiCheck, which drives the control without XrmToolBox connections ----------
        internal void UseSessionForTesting(MigrationSession session)
        {
            _testing = true;
            _session = session;
            _lblSource.Text = "Source: " + session.Source.Name;
            _lblTarget.Text = "Target: " + session.Target.Name;
            UpdateButtons();
        }
        internal void CompareForTesting() => Compare();
        internal void PlanForTesting() => BuildPlan();
        internal void DryRunForTesting() => Run(dry: true);
        internal void ShowTabForTesting(int index) => _tabs.SelectedIndex = index;
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
        TextBox _search;
        readonly Dictionary<string, CheckBox> _statusFilters = new Dictionary<string, CheckBox>();
        CheckBox _selectAll, _includeDeps;
        Label _selectionCount;
        TreeView _tree;
        Label _detailTitle, _detailStatus;
        ListView _fields, _needs, _under;
        TextBox _notices;
        // Plan
        Label _planSummary;
        ListView _planList;
        Button _btnAddMissing;
        // Run
        Label _runTitle, _runCurrent;
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
            ResetSession();
            _lblSource.Text = "Source: " + (detail?.ConnectionName ?? "not connected");
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

        void ResetSession()
        {
            _session = null; _diff = null; _selection = null; _plan = null; _dryRunPlanId = null;
            _tree?.Nodes.Clear();
            _planList?.Items.Clear();
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
                    _selection = new Selection(_diff);
                    _selection.SelectAll();
                    _plan = null; _dryRunPlanId = null;
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

        IEnumerable<RecordDiff> Shown(TableDiff t)
        {
            var q = (_search.Text ?? "").Trim();
            return t.Records
                .Where(r => _statusFilters.TryGetValue(r.Status, out var cb) && cb.Checked)
                .Where(r => q.Length == 0 || r.FullName.IndexOf(q, StringComparison.OrdinalIgnoreCase) >= 0 || t.Label.IndexOf(q, StringComparison.OrdinalIgnoreCase) >= 0)
                .OrderBy(r => r.FullName, StringComparer.CurrentCultureIgnoreCase);
        }

        void RebuildTree()
        {
            if (_diff == null) return;
            _tree.BeginUpdate();
            _tree.Nodes.Clear();
            foreach (var group in _diff.Tables.GroupBy(t => string.IsNullOrEmpty(t.Group) ? "Other" : t.Group).OrderBy(g => g.Min(t => t.Stage)))
            {
                var gNode = new TreeNode(group.Key) { Tag = "group", NodeFont = new Font(_tree.Font, FontStyle.Bold) };
                foreach (var t in group)
                {
                    var rows = Shown(t).ToList();
                    if (rows.Count == 0) continue;
                    var tNode = new TreeNode($"{t.Label} ({rows.Count})") { Tag = t };
                    foreach (var r in rows)
                    {
                        var st = Statuses.First(x => x.Status == r.Status);
                        tNode.Nodes.Add(new TreeNode($"{r.FullName}   [{st.Label}]") { Tag = r, ForeColor = r.IsMovable ? Ink : Muted, ToolTipText = st.Label });
                    }
                    gNode.Nodes.Add(tNode);
                }
                if (gNode.Nodes.Count > 0) _tree.Nodes.Add(gNode);
            }
            _tree.ExpandAll();
            if (_tree.Nodes.Count > 0) _tree.Nodes[0].EnsureVisible();
            _tree.EndUpdate();
            SyncChecks();
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

        void SyncChecks()
        {
            if (_selection == null) return;
            _syncingChecks = true;
            _tree.BeginUpdate();
            foreach (TreeNode g in _tree.Nodes)
            {
                foreach (TreeNode t in g.Nodes)
                {
                    foreach (TreeNode r in t.Nodes) r.Checked = _selection.Selected.Contains(((RecordDiff)r.Tag).Ref);
                    var movable = t.Nodes.Cast<TreeNode>().Where(n => ((RecordDiff)n.Tag).IsMovable).ToList();
                    t.Checked = movable.Count > 0 && movable.All(n => n.Checked);
                }
                g.Checked = g.Nodes.Cast<TreeNode>().Any() && g.Nodes.Cast<TreeNode>().All(n => n.Checked || !RecordNodes(n).Any(r => ((RecordDiff)r.Tag).IsMovable));
            }
            _tree.EndUpdate();
            var shown = AllRecordNodes().Select(n => (RecordDiff)n.Tag).Where(r => r.IsMovable).ToList();
            var selectedShown = shown.Count(r => _selection.Selected.Contains(r.Ref));
            _selectAll.CheckState = shown.Count == 0 || selectedShown == 0 ? CheckState.Unchecked : selectedShown == shown.Count ? CheckState.Checked : CheckState.Indeterminate;
            _selectAll.Text = shown.Count == _diff.AllRecords.Count(r => r.IsMovable) ? $"Select all {shown.Count} records" : $"Select all {shown.Count} records shown";
            _selectionCount.Text = $"{_selection.Selected.Count} of {_diff.AllRecords.Count(r => r.IsMovable)} selected";
            _syncingChecks = false;
            UpdateButtons();
        }

        void OnTreeCheck(object sender, TreeViewEventArgs e)
        {
            if (_syncingChecks || _selection == null || e.Action == TreeViewAction.Unknown) return;
            var refs = (e.Node.Tag is RecordDiff rd ? new[] { e.Node } : RecordNodes(e.Node))
                .Select(n => (RecordDiff)n.Tag).Where(r => r.IsMovable).Select(r => r.Ref).ToList();
            if (refs.Count > 0)
            {
                var before = _selection.Selected.Count;
                _selection.Set(refs, e.Node.Checked);
                var brought = _selection.Selected.Count - before - (e.Node.Checked ? refs.Count(r => true) : 0);
                if (e.Node.Tag is RecordDiff && e.Node.Checked && brought > 0)
                    Notify($"Selected with everything under it and what that uses: {brought} more record{(brought == 1 ? "" : "s")}.", null);
            }
            _plan = null; _dryRunPlanId = null;
            SyncChecks();
            ShowDetails(_tree.SelectedNode?.Tag as RecordDiff);
        }

        void OnSelectAll(object sender, EventArgs e)
        {
            if (_syncingChecks || _selection == null) return;
            var shown = AllRecordNodes().Select(n => (RecordDiff)n.Tag).Where(r => r.IsMovable).Select(r => r.Ref).ToList();
            var on = _selectAll.CheckState != CheckState.Unchecked;
            if (_selectAll.CheckState == CheckState.Indeterminate) { on = true; }
            _selection.Set(shown, on);
            _plan = null; _dryRunPlanId = null;
            SyncChecks();
        }

        // --- Details -------------------------------------------------------------------------------

        void ShowDetails(RecordDiff r)
        {
            _fields.Items.Clear(); _needs.Items.Clear(); _under.Items.Clear();
            if (r == null || _diff == null) { _detailTitle.Text = "Select a record"; _detailStatus.Text = ""; return; }
            var st = Statuses.First(x => x.Status == r.Status);
            _detailTitle.Text = r.FullName;
            _detailStatus.Text = $"{_diff.TablePlans[r.Table].Table.DisplayLabel} · {st.Label}" + (r.Note != null ? " · " + r.Note : "");
            _detailStatus.ForeColor = st.Color;

            foreach (var f in r.Fields) _fields.Items.Add(new ListViewItem(new[] { f.Label, f.Source ?? "(empty)", f.Kind == "definition" ? "" : f.Target ?? "(empty)" }));
            if (r.Fields.Count == 0) _fields.Items.Add(new ListViewItem(new[] { r.Status == RecordStatus.MissingInTarget ? "New in the target" : "No differences", "", "" }) { ForeColor = Muted });

            foreach (var d in r.DependsOn)
            {
                var inTarget = _diff.Maps.TargetKeyToGuid.ContainsKey(d.Ref);
                var dep = _diff.Find(d.Ref);
                var state = inTarget ? "in the target" : dep?.Status == RecordStatus.MissingInTarget ? (_selection.Selected.Contains(d.Ref) ? "new · selected" : "new · not selected") : "missing";
                if (d.Deferred) state += " · linked at the end";
                _needs.Items.Add(new ListViewItem(new[] { d.Label, d.Via, state }) { ForeColor = state.StartsWith("missing") || state.Contains("not selected") ? Red : Ink });
            }
            foreach (var refUnder in _selection.OwnedBy(r.Ref))
            {
                var u = _diff.Find(refUnder);
                if (u == null) continue;
                _under.Items.Add(new ListViewItem(new[] { u.FullName, _diff.TablePlans[u.Table].Table.DisplayLabel, Statuses.First(x => x.Status == u.Status).Label + (_selection.Selected.Contains(refUnder) ? " · selected" : "") }));
            }
        }

        // --- Plan ----------------------------------------------------------------------------------

        void BuildPlan()
        {
            if (_diff == null || _selection == null) return;
            _plan = Session().BuildPlan(_selection.Selected.ToList(), _includeDeps.Checked);
            _dryRunPlanId = null;
            ShowPlan();
            _tabs.SelectedTab = _tabPlan;
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

            // Left: filters, select all, tree.
            var top = new FlowLayoutPanel { Dock = DockStyle.Top, Height = 64, Padding = new Padding(4), WrapContents = true };
            _search = new TextBox { Width = 220 };
            _search.TextChanged += (s, e) => RebuildTree();
            top.Controls.Add(new Label { Text = "Find:", AutoSize = true, Padding = new Padding(0, 6, 0, 0) });
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
            var hint = new Label
            {
                Dock = DockStyle.Bottom, Height = 36, ForeColor = Muted, Padding = new Padding(6, 2, 6, 2),
                Text = "Ticking a record also ticks everything under it and what that uses: a workstream brings its routing configuration, work classification and route-to-queue steps, their rulesets and queues.",
            };
            _includeDeps = new CheckBox { Text = "Add the records they need to the plan", Checked = true, Dock = DockStyle.Bottom, Height = 24, Padding = new Padding(6, 0, 0, 0) };
            split.Panel1.Controls.Add(_tree);
            split.Panel1.Controls.Add(selectRow);
            split.Panel1.Controls.Add(top);
            split.Panel1.Controls.Add(_includeDeps);
            split.Panel1.Controls.Add(hint);

            // Right: details.
            var right = new Panel { Dock = DockStyle.Fill, Padding = new Padding(8) };
            split.Panel2.Controls.Add(right);
            _detailTitle = new Label { Text = "Compare to see what differs", Dock = DockStyle.Top, Height = 28, Font = new Font("Segoe UI Semilight", 13f), ForeColor = Ink, AutoEllipsis = true };
            _detailStatus = new Label { Dock = DockStyle.Top, Height = 22, ForeColor = Muted, AutoEllipsis = true };
            _fields = NewList(("Setting", 180), ("Source", 220), ("Target", 220));
            _needs = NewList(("Needs", 300), ("Through", 160), ("State", 180));
            _under = NewList(("Under it", 340), ("Table", 160), ("Status", 160));
            _notices = new TextBox { Dock = DockStyle.Bottom, Height = 90, Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical, BorderStyle = BorderStyle.None, BackColor = ColorTranslator.FromHtml("#F8FAFC") };
            var grid = new TableLayoutPanel { Dock = DockStyle.Fill, RowCount = 6, ColumnCount = 1 };
            grid.RowStyles.Add(new RowStyle(SizeType.Absolute, 24)); grid.RowStyles.Add(new RowStyle(SizeType.Percent, 34));
            grid.RowStyles.Add(new RowStyle(SizeType.Absolute, 24)); grid.RowStyles.Add(new RowStyle(SizeType.Percent, 33));
            grid.RowStyles.Add(new RowStyle(SizeType.Absolute, 24)); grid.RowStyles.Add(new RowStyle(SizeType.Percent, 33));
            grid.Controls.Add(Heading("What differs"), 0, 0); grid.Controls.Add(_fields, 0, 1);
            grid.Controls.Add(Heading("What it needs"), 0, 2); grid.Controls.Add(_needs, 0, 3);
            grid.Controls.Add(Heading("Everything under it"), 0, 4); grid.Controls.Add(_under, 0, 5);
            right.Controls.Add(grid);
            right.Controls.Add(_notices);
            right.Controls.Add(_detailStatus);
            right.Controls.Add(_detailTitle);
        }

        void BuildPlanTab()
        {
            var top = new Panel { Dock = DockStyle.Top, Height = 40, Padding = new Padding(8, 8, 8, 4) };
            _planSummary = new Label { Dock = DockStyle.Fill, Text = "Select what to move on the Review tab, then Check the plan.", ForeColor = Muted };
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
            _runTitle = new Label { Dock = DockStyle.Top, Height = 24, Font = new Font("Segoe UI Semibold", 10f), ForeColor = Ink, Text = "Dry-run the plan first; Apply unlocks after a dry run of the same plan." };
            _runProgress = new ProgressBar { Dock = DockStyle.Top, Height = 14 };
            _runCurrent = new Label { Dock = DockStyle.Top, Height = 22, ForeColor = Muted };
            top.Controls.Add(_runCurrent); top.Controls.Add(_runProgress); top.Controls.Add(_runTitle);

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
