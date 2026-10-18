using System.Collections.Generic;
using System.Linq;

namespace CcAlm.Core.Engine
{
    /// <summary>A record pointing at another, and the column it points through.</summary>
    public sealed class Use
    {
        public string Ref { get; set; }
        public string Via { get; set; }
        public bool Deferred { get; set; }
    }

    /// <summary>
    /// Where every record of a compare sits. A record's owner is the parent its match key names - a
    /// routing step's routing configuration, that configuration's workstream - so each record has
    /// one place in a tree. Everything else it points at (the queue a step routes to, the template a
    /// workstream names) is a use: it is shown where it is used, and the same record can be used in
    /// many places. This is what the tool reads to show the structure instead of a list per table;
    /// what gets selected with a record is Selection's business, and wider.
    /// </summary>
    public sealed class Hierarchy
    {
        static readonly string[] NoRefs = new string[0];
        static readonly Use[] NoUses = new Use[0];

        readonly Dictionary<string, string> _owner = new Dictionary<string, string>();
        readonly Dictionary<string, List<string>> _children = new Dictionary<string, List<string>>();
        readonly Dictionary<string, List<Use>> _uses = new Dictionary<string, List<Use>>();
        readonly Dictionary<string, List<Use>> _usedBy = new Dictionary<string, List<Use>>();
        readonly List<string> _roots = new List<string>();

        public static Hierarchy Of(DiffModel diff)
        {
            var h = new Hierarchy();
            var records = diff.AllRecords.ToList();
            var byRef = new Dictionary<string, RecordDiff>();
            foreach (var r in records) if (!byRef.ContainsKey(r.Ref)) byRef[r.Ref] = r;

            foreach (var r in records)
            {
                // The owner first, so a record that is both owner and use is read as the owner.
                var owner = r.DependsOn.FirstOrDefault(d => d.Owner && d.Ref != r.Ref && byRef.ContainsKey(d.Ref));
                if (owner != null)
                {
                    h._owner[r.Ref] = owner.Ref;
                    h.Add(h._children, owner.Ref, r.Ref);
                }
                foreach (var d in r.DependsOn)
                {
                    if (d == owner || d.Ref == r.Ref || !byRef.ContainsKey(d.Ref)) continue;
                    var use = new Use { Ref = d.Ref, Via = d.Via, Deferred = d.Deferred };
                    h.Add(h._uses, r.Ref, use);
                    h.Add(h._usedBy, d.Ref, new Use { Ref = r.Ref, Via = d.Via, Deferred = d.Deferred });
                }
            }

            // Sort everything the way the tool reads records: the write order, then the name.
            var order = new Dictionary<string, int>();
            if (diff.TablePlans != null)
                foreach (var kv in diff.TablePlans) order[kv.Key] = kv.Value.Table.Order;
            int Order(string reference) => byRef.TryGetValue(reference, out var r) && order.TryGetValue(r.Table, out var o) ? o : int.MaxValue;
            string Name(string reference) => byRef.TryGetValue(reference, out var r) ? r.FullName : reference;
            void Sort(List<string> list) => list.Sort((a, b) => Order(a) != Order(b) ? Order(a).CompareTo(Order(b)) : string.Compare(Name(a), Name(b), System.StringComparison.CurrentCultureIgnoreCase));
            foreach (var kv in h._children) Sort(kv.Value);
            foreach (var kv in h._uses) kv.Value.Sort((a, b) => Order(a.Ref) != Order(b.Ref) ? Order(a.Ref).CompareTo(Order(b.Ref)) : string.Compare(Name(a.Ref), Name(b.Ref), System.StringComparison.CurrentCultureIgnoreCase));
            foreach (var kv in h._usedBy) kv.Value.Sort((a, b) => Order(a.Ref) != Order(b.Ref) ? Order(a.Ref).CompareTo(Order(b.Ref)) : string.Compare(Name(a.Ref), Name(b.Ref), System.StringComparison.CurrentCultureIgnoreCase));

            foreach (var r in records) if (!h._owner.ContainsKey(r.Ref)) h._roots.Add(r.Ref);
            // A record whose owners run in a circle belongs to no root; it becomes one itself, so
            // that walking the roots still reaches every record exactly once.
            var reached = new HashSet<string>();
            foreach (var root in h._roots) foreach (var x in h.Branch(root)) reached.Add(x);
            foreach (var r in records) if (!reached.Contains(r.Ref)) h._roots.Add(r.Ref);
            Sort(h._roots);
            return h;
        }

        void Add<T>(Dictionary<string, List<T>> map, string key, T value)
        {
            if (!map.TryGetValue(key, out var list)) map[key] = list = new List<T>();
            list.Add(value);
        }

        /// <summary>The parent the record is matched under, or null when it stands on its own.</summary>
        public string OwnerOf(string reference) => reference != null && _owner.TryGetValue(reference, out var o) ? o : null;

        /// <summary>The records matched under this one, in write order.</summary>
        public IReadOnlyList<string> ChildrenOf(string reference) =>
            reference != null && _children.TryGetValue(reference, out var c) ? (IReadOnlyList<string>)c : NoRefs;

        /// <summary>What this record points at besides its owner: the queue it routes to, the template it names.</summary>
        public IReadOnlyList<Use> UsesOf(string reference) =>
            reference != null && _uses.TryGetValue(reference, out var u) ? (IReadOnlyList<Use>)u : NoUses;

        /// <summary>The records that point at this one. Children are not uses; they are under it.</summary>
        public IReadOnlyList<Use> UsedBy(string reference) =>
            reference != null && _usedBy.TryGetValue(reference, out var u) ? (IReadOnlyList<Use>)u : NoUses;

        /// <summary>Every record that stands on its own, in write order: where the tree starts.</summary>
        public IReadOnlyList<string> Roots => _roots;

        /// <summary>Everything under the record, however deep, the nearest first.</summary>
        public List<string> Descendants(string reference)
        {
            var result = new List<string>();
            var seen = new HashSet<string> { reference };
            var queue = new Queue<string>();
            queue.Enqueue(reference);
            while (queue.Count > 0)
                foreach (var c in ChildrenOf(queue.Dequeue()))
                    if (seen.Add(c)) { result.Add(c); queue.Enqueue(c); }
            return result;
        }

        List<string> Branch(string reference)
        {
            var all = Descendants(reference);
            all.Insert(0, reference);
            return all;
        }

        /// <summary>The owners above the record, the outermost first; empty when it stands on its own.</summary>
        public List<string> PathTo(string reference)
        {
            var path = new List<string>();
            var seen = new HashSet<string> { reference };
            for (var o = OwnerOf(reference); o != null && seen.Add(o); o = OwnerOf(o)) path.Insert(0, o);
            return path;
        }
    }
}
