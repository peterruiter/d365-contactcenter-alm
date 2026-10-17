using System;
using System.Diagnostics;
using System.Linq;
using CcAlm.Core.Engine;
using CcAlm.XrmToolBox;
using Microsoft.Xrm.Tooling.Connector;

// Usage: CcAlm.LiveCheck <sourceUrl> <targetUrl> [azSubscription]
// Reads both environments with the C# engine (read-only) and prints the compare and plan summary.
static class Program
{
    static string Subscription;

    /// <summary>Tokens from az for the SDK client, cached per host.</summary>
    sealed class AzAuth : IOverrideAuthHookWrapper
    {
        readonly System.Collections.Generic.Dictionary<string, string> _cache = new System.Collections.Generic.Dictionary<string, string>();
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

    static int Main(string[] a)
    {
        Subscription = a.Length > 2 ? a[2] : null;
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
        var plan = session.BuildPlan(null);
        Console.WriteLine($"plan: {plan.Summary.Ready} ready, {plan.Summary.Blocked} blocked");
        var dry = session.Run(plan, dryRun: true);
        Console.WriteLine($"dry run: {dry.Summary.Created} create, {dry.Summary.Updated} update, {dry.Summary.Linked} link, {dry.Summary.Skipped} skipped, {dry.Summary.Failed} failed");
        return 0;
    }
}
