using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Reflection;
using System.Windows.Forms;
using CcAlm.Core.Engine;
using CcAlm.Core.Tests;
using CcAlm.XrmToolBox;

static class Program
{
    [STAThread]
    static void Main(string[] args)
    {
        var xtb = Environment.GetEnvironmentVariable("XTB_PATH") ?? Path.Combine(Path.GetTempPath(), "xtb-runtime");
        var outDir = args.Length > 0 ? args[0] : Path.Combine(Path.GetTempPath(), "ccalm-uicheck");
        Directory.CreateDirectory(outDir);
        AppDomain.CurrentDomain.AssemblyResolve += (s, e) =>
        {
            var path = Path.Combine(xtb, new AssemblyName(e.Name).Name + ".dll");
            return File.Exists(path) ? Assembly.LoadFrom(path) : null;
        };
        if (args.Length > 1 && args[1] == "--mef") { Mef(outDir); return; }
        // --recorded <dir>: drive the tool with a recorded compare of two real environments
        // (tests/fixtures/recorded/<name>) instead of the synthetic scenario, to see the tree at
        // the size it has in practice.
        Run(outDir, args.Length > 2 && args[1] == "--recorded" ? args[2] : null);
    }

    // Finds the tool the way XrmToolBox does: an MEF export of IXrmToolBoxPlugin with its metadata.
    static void Mef(string outDir)
    {
        var log = new StringWriter();
        var catalog = new System.ComponentModel.Composition.Hosting.AssemblyCatalog(typeof(Plugin).Assembly);
        foreach (var part in catalog.Parts)
            foreach (var ex in part.ExportDefinitions)
            {
                log.WriteLine("export: " + ex.ContractName);
                foreach (var k in new[] { "Name", "Description", "BackgroundColor", "PrimaryFontColor", "SecondaryFontColor" }) log.WriteLine($"  {k}: {ex.Metadata[k]}");
                log.WriteLine($"  SmallImageBase64: {((string)ex.Metadata["SmallImageBase64"]).Length} chars, BigImageBase64: {((string)ex.Metadata["BigImageBase64"]).Length} chars");
            }
        using (var container = new System.ComponentModel.Composition.Hosting.CompositionContainer(catalog))
            foreach (var p in container.GetExportedValues<XrmToolBox.Extensibility.Interfaces.IXrmToolBoxPlugin>())
                log.WriteLine($"plugin: {p.GetType().FullName}, control {p.GetControl().GetType().Name}");
        File.WriteAllText(Path.Combine(outDir, "mef.txt"), log.ToString());
    }

    static MigrationSession Recorded(string dir)
    {
        var source = new FakeDataverse("Dev", "https://dev.recorded.example", FakeDataverse.LoadMetadata(Path.Combine(dir, "source.metadata.json")));
        source.LoadRecords(Path.Combine(dir, "source.records.json"));
        var target = new FakeDataverse("Test", "https://test.recorded.example", FakeDataverse.LoadMetadata(Path.Combine(dir, "target.metadata.json")));
        target.LoadRecords(Path.Combine(dir, "target.records.json"));
        return new MigrationSession(source, target);
    }

    static void Run(string outDir, string recordedDir = null)
    {
        Application.EnableVisualStyles();
        var form = new Form { Width = 1500, Height = 900, StartPosition = FormStartPosition.Manual, Location = new Point(20, 20), Text = "Contact Center ALM - UI check" };
        var control = (MainControl)new Plugin().GetControl();
        control.Dock = DockStyle.Fill;
        form.Controls.Add(control);
        var log = new StringWriter();
        var scenario = new Scenario();
        // Records to put on screen: a container, something shared by several records, and one the
        // plan check blocks. The two sets of data have different names for them.
        var container = recordedDir != null ? "Voice" : "Mortgage chat";
        var shared = recordedDir != null ? "Default messaging queue" : "Mortgage queue";
        var blocked = recordedDir != null ? "Microsoft 365 Copilot workstream" : "Mortgage WhatsApp";
        var steps = new Action[]
        {
            () => { control.UseSessionForTesting(recordedDir != null ? Recorded(recordedDir) : new MigrationSession(scenario.Dev, scenario.Test)); control.CompareForTesting(); },
            () => log.WriteLine(control.TreeSummaryForTesting()),
            () => { control.SelectFirstRecordForTesting(container); },
            () => Shot(form, outDir, "1-review.png", log),
            // A queue: used by a workstream and by a ruleset, so "Where it is used" has something to say.
            () => { control.SelectFirstRecordForTesting(shared); },
            () => Shot(form, outDir, "1b-review-used-by.png", log),
            () => control.ShowViewForTesting("By table"),
            () => Shot(form, outDir, "1c-review-by-table.png", log),
            // Opening the tabs without touching the toolbar: they must fill themselves.
            () => { control.ShowViewForTesting("By structure"); control.ShowTabForTesting(1); },
            () => Shot(form, outDir, "2-plan.png", log),
            () => control.ShowTabForTesting(2),
            () => Shot(form, outDir, "2a-run-before-running.png", log),
            // Back to the tree: it now says which workstream or channel the blocked records sit in.
            () => { control.ShowTabForTesting(0); control.SelectFirstRecordForTesting(blocked); },
            () => Shot(form, outDir, "2b-review-blocked.png", log),
            () => control.DryRunForTesting(),
            () => { },
            () => Shot(form, outDir, "3-run.png", log),
            // Last, because the second one empties the tree on purpose: XrmToolBox raises the
            // connection again when its metadata cache has loaded, and the compare has to survive
            // that; a different source environment has to clear it.
            () => { control.ShowTabForTesting(0); control.SourceConnectionForTesting("Dev", recordedDir != null ? "https://dev.recorded.example" : "https://dev.example"); log.WriteLine("after the same connection again: " + FirstLine(control.TreeSummaryForTesting())); },
            () => { control.SourceConnectionForTesting("Other", "https://other.example"); log.WriteLine("after a different environment: " + FirstLine(control.TreeSummaryForTesting())); },
            () => Shot(form, outDir, "4-review-after-other-environment.png", log),
            () => form.Close(),
        };
        int i = 0;
        var timer = new Timer { Interval = 1500 };
        timer.Tick += (s, e) =>
        {
            try { steps[i++](); }
            catch (Exception ex) { log.WriteLine("step " + i + ": " + ex); }
            if (i >= steps.Length) { timer.Stop(); File.WriteAllText(Path.Combine(outDir, "log.txt"), log.ToString()); }
        };
        form.Shown += (s, e) => timer.Start();
        Application.Run(form);
        File.WriteAllText(Path.Combine(outDir, "log.txt"), log.ToString() + "done");
    }

    static string FirstLine(string text) => new StringReader(text).ReadLine();

    static void Shot(Form form, string dir, string name, TextWriter log)
    {
        using (var bmp = new Bitmap(form.Width, form.Height))
        {
            // From the screen, which shows the window as Windows draws it. Without an interactive
            // desktop (a build agent, a terminal without one) that cannot be read, so the window
            // draws itself instead: the same layout, without the frame.
            try
            {
                // CCALM_UICHECK_DRAW=1: never read the screen, so another window cannot end up in
                // the picture. For screenshots meant for other people.
                if (Environment.GetEnvironmentVariable("CCALM_UICHECK_DRAW") == "1") throw new InvalidOperationException("drawing was asked for");
                using (var g = Graphics.FromImage(bmp)) g.CopyFromScreen(form.Location, Point.Empty, form.Size);
            }
            catch (Exception ex)
            {
                log.WriteLine("no screen (" + ex.GetType().Name + "), drawing the window itself");
                form.DrawToBitmap(bmp, new Rectangle(0, 0, form.Width, form.Height));
            }
            bmp.Save(Path.Combine(dir, name), ImageFormat.Png);
        }
        log.WriteLine("saved " + name);
    }
}
