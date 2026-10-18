using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using CcAlm.Core.Engine;
using CcAlm.XrmToolBox;
using Microsoft.Xrm.Tooling.Connector;

// Usage: CcAlm.LiveCheck <sourceUrl> <targetUrl> [--subscription <name>] [--only <table,table>] [--apply]
//
// Reads both environments with the C# engine and prints the compare, the plan and a dry run. Read-only,
// unless --apply is given: that writes, and --only keeps it to the tables named (with the records those
// need). Every apply writes its snapshot next to the exe, so it can be rolled back.
static class Program
{
    static string Subscription;

    /// <summary>Tokens from az for the SDK client, cached per host.</summary>
    sealed class AzAuth : IOverrideAuthHookWrapper
    {
        readonly Dictionary<string, string> _cache = new Dictionary<string, string>();
        public string GetAuthToken(Uri connectedUri)
        {
            var host = $"{connectedUri.Scheme}://{connectedUri.Host}";
            if (_cache.TryGetValue(host, out var t)) return t;
            var args = $"account get-access-token --resource {host} --query accessToken -o tsv" + (Subscription != null ? $" --subscription {Subscription}" : "");
            var p = Process.Start(new ProcessStartInfo("cmd.exe", "/c az " + args) { RedirectStandardOutput = true, UseShellExecute = false, CreateNoWindow = true });
            var token = p.StandardOutput.ReadToEnd().Trim();
            p.WaitForExit();
            return _cache[host] = token;
        }
    }

    static string Option(string[] a, string name) =>
        Enumerable.Range(0, a.Length - 1).Where(i => a[i] == name).Select(i => a[i + 1]).FirstOrDefault();

    static int Main(string[] a)
    {
        Subscription = Option(a, "--subscription") ?? (a.Length > 2 && !a[2].StartsWith("--") ? a[2] : null);
        var only = (Option(a, "--only") ?? "").Split(new[] { ',' }, StringSplitOptions.RemoveEmptyEntries).Select(x => x.Trim()).ToList();
        var apply = a.Contains("--apply");

        CrmServiceClient.AuthOverrideHook = new AzAuth();
        CrmServiceClient Client(string url)
        {
            var c = new CrmServiceClient(new Uri(url), true);
            if (!c.IsReady) throw new Exception($"Could not connect to {url}: {c.LastCrmError}");
            return c;
        }
        var sw = Stopwatch.StartNew();
        var source = new SdkDataverse(Client(a[0]), "Source", a[0]);
        var target = new SdkDataverse(Client(a[1]), "Target", a[1]);
        var session = new MigrationSession(source, target);
        var diff = session.Compare(m => Console.Error.WriteLine(m));
        var s = diff.Summary;
        Console.WriteLine($"compare: {s.MissingInTarget} new, {s.Changed} changed, {s.ExtraInTarget} extra, {s.Equal} same, {s.Ambiguous} ambiguous ({sw.Elapsed.TotalSeconds:0}s)");
        foreach (var t in diff.Tables)
            Console.WriteLine($"  {t.Table}: " + string.Join(", ", t.Records.GroupBy(r => r.Status).OrderBy(g => g.Key).Select(g => $"{g.Key} {g.Count()}")));

        foreach (var d in diff.DetectOnly)
            Console.WriteLine($"  set up by hand: {d.Label} '{d.Record}': {d.Message}");
        foreach (var n in diff.Notices)
            Console.WriteLine($"  note: {n.Message}");

        // Everything that can move, or only the tables asked for, with what those need.
        List<string> selection = null;
        if (only.Count > 0)
        {
            selection = diff.AllRecords.Where(r => r.IsMovable && only.Contains(r.Table)).Select(r => r.Ref).ToList();
            Console.WriteLine($"only {string.Join(", ", only)}: {selection.Count} record(s) selected");
        }
        var plan = session.BuildPlan(selection);
        Console.WriteLine($"plan: {plan.Summary.Ready} ready, {plan.Summary.Blocked} blocked");
        foreach (var o in plan.Operations)
            Console.WriteLine($"  {o.Status,-7} {o.Op,-6} {o.TableLabel}: {o.FullName}"
                + (o.AutoIncluded ? $"  (needed by {string.Join(", ", o.NeededBy)})" : "")
                + (o.Blockers.Count > 0 ? "  " + string.Join(" ", o.Blockers.Select(b => b.Message)) : ""));

        var dry = session.Run(plan, dryRun: true);
        Console.WriteLine($"dry run: {dry.Summary.Created} create, {dry.Summary.Updated} update, {dry.Summary.Linked} link, {dry.Summary.Skipped} skipped, {dry.Summary.Failed} failed");
        if (!apply) return 0;

        // --apply: the same plan, for real.
        var dir = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "runs");
        Directory.CreateDirectory(dir);
        Console.WriteLine($"APPLYING to {a[1]}");
        var run = session.Run(plan, dryRun: false, saveSnapshot: snap => RunStore.Save(Path.Combine(dir, $"snapshot-{snap.RunId}.json"), snap));
        RunStore.Save(Path.Combine(dir, $"run-{run.RunId}.json"), run);
        Console.WriteLine($"apply: {run.Summary.Created} created, {run.Summary.Updated} updated, {run.Summary.Linked} linked, {run.Summary.Skipped} skipped, {run.Summary.Failed} failed  (run {run.RunId})");
        foreach (var i in run.Items.Where(i => i.Outcome == Outcome.Failed || i.Outcome == Outcome.Skipped || i.Outcome == Outcome.Blocked))
            Console.WriteLine($"  {i.Outcome}: {i.TableLabel} '{i.FullName}': {i.Message}");
        var v = run.Verification;
        if (v != null)
        {
            Console.WriteLine($"check afterwards: {v.State} - {v.Matched} of {v.Checked} read back the same as in the source");
            foreach (var d in v.Differences)
                Console.WriteLine($"  differs: {d.TableLabel} '{d.FullName}': {d.Message}");
        }
        Console.WriteLine($"snapshot in {dir}");
        return run.Summary.Failed > 0 ? 1 : 0;
    }
}
