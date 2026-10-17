using System.Collections.Generic;
using System.Linq;

namespace CcAlm.Core.Engine
{
    /// <summary>
    /// What gets selected with a record. Ticking a record ticks everything under it - the records
    /// pointing at it through a lookup to a table written before them (a routing step to its routing
    /// configuration, that to its workstream) - and everything those use that differs: the rulesets the
    /// steps run, the queues those route to, the templates the workstream names. Unticking takes that
    /// away again, except what another ticked record still needs.
    /// </summary>
    public sealed class Selection
    {
        readonly DiffModel _diff;
        readonly Dictionary<string, List<string>> _children = new Dictionary<string, List<string>>();
        readonly HashSet<string> _ticked = new HashSet<string>();

        public Selection(DiffModel diff)
        {
            _diff = diff;
            foreach (var r in diff.AllRecords)
                foreach (var d in r.DependsOn)
                {
                    if (d.Kind != null && d.Kind != "lookup") continue;
                    if (d.Deferred) continue;   // a reference to a later table, not ownership
                    if (!_children.TryGetValue(d.Ref, out var list)) _children[d.Ref] = list = new List<string>();
                    list.Add(r.Ref);
                }
        }

        public HashSet<string> Selected { get; } = new HashSet<string>();

        /// <summary>The record, everything under it, and what those use that differs; only movable records.</summary>
        public List<string> BundleOf(string start)
        {
            var owned = new HashSet<string> { start };
            var queue = new Queue<string>(owned);
            while (queue.Count > 0)
                if (_children.TryGetValue(queue.Dequeue(), out var kids))
                    foreach (var k in kids)
                        if (owned.Add(k)) queue.Enqueue(k);

            var all = new HashSet<string>(owned);
            var next = new Queue<string>(owned);
            while (next.Count > 0)
            {
                var rec = _diff.Find(next.Dequeue());
                if (rec == null) continue;
                foreach (var d in rec.DependsOn)
                {
                    var dep = _diff.Find(d.Ref);
                    if (dep == null || !dep.IsMovable || !all.Add(d.Ref)) continue;
                    next.Enqueue(d.Ref);
                }
            }
            return all.Where(x => _diff.Find(x)?.IsMovable == true).ToList();
        }

        /// <summary>Only what sits under the record (no shared dependencies), for showing "under it".</summary>
        public List<string> OwnedBy(string start)
        {
            var owned = new List<string>();
            var seen = new HashSet<string> { start };
            var queue = new Queue<string>(seen);
            while (queue.Count > 0)
                if (_children.TryGetValue(queue.Dequeue(), out var kids))
                    foreach (var k in kids)
                        if (seen.Add(k)) { owned.Add(k); queue.Enqueue(k); }
            return owned;
        }

        public void Set(IEnumerable<string> refs, bool on)
        {
            var list = refs.ToList();
            if (on)
            {
                foreach (var r in list)
                {
                    _ticked.Add(r);
                    foreach (var x in BundleOf(r)) Selected.Add(x);
                }
                return;
            }
            var removed = new HashSet<string>(list.SelectMany(BundleOf).Concat(list));
            foreach (var x in removed) { Selected.Remove(x); _ticked.Remove(x); }
            foreach (var t in _ticked.ToList())
                if (Selected.Contains(t))
                    foreach (var x in BundleOf(t)) Selected.Add(x);
        }

        public void Toggle(string reference) => Set(new[] { reference }, !Selected.Contains(reference));

        public void SelectAll()
        {
            Clear();
            Set(_diff.AllRecords.Where(r => r.IsMovable).Select(r => r.Ref), true);
        }

        public void Clear() { Selected.Clear(); _ticked.Clear(); }
    }
}
