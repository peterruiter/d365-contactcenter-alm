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
        Run(outDir);
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

    static void Run(string outDir)
    {
        Application.EnableVisualStyles();
        var form = new Form { Width = 1500, Height = 900, StartPosition = FormStartPosition.Manual, Location = new Point(20, 20), Text = "Contact Center ALM - UI check" };
        var control = (MainControl)new Plugin().GetControl();
        control.Dock = DockStyle.Fill;
        form.Controls.Add(control);
        var log = new StringWriter();
        var scenario = new Scenario();
        var steps = new Action[]
        {
            () => { control.UseSessionForTesting(new MigrationSession(scenario.Dev, scenario.Test)); control.CompareForTesting(); },
            () => { control.SelectFirstRecordForTesting("Mortgage chat"); },
            () => Shot(form, outDir, "1-review.png", log),
            // A queue: used by a workstream and by a ruleset, so "Where it is used" has something to say.
            () => { control.SelectFirstRecordForTesting("Mortgage queue"); },
            () => Shot(form, outDir, "1b-review-used-by.png", log),
            () => control.ShowViewForTesting("By table"),
            () => Shot(form, outDir, "1c-review-by-table.png", log),
            () => { control.ShowViewForTesting("By structure"); control.PlanForTesting(); },
            () => Shot(form, outDir, "2-plan.png", log),
            // Back to the tree: it now says which workstream or channel the blocked records sit in.
            () => { control.ShowTabForTesting(0); control.SelectFirstRecordForTesting("Mortgage WhatsApp"); },
            () => Shot(form, outDir, "2b-review-blocked.png", log),
            () => control.DryRunForTesting(),
            () => { },
            () => Shot(form, outDir, "3-run.png", log),
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

    static void Shot(Form form, string dir, string name, TextWriter log)
    {
        using (var bmp = new Bitmap(form.Width, form.Height))
        {
            // From the screen, which shows the window as Windows draws it. Without an interactive
            // desktop (a build agent, a terminal without one) that cannot be read, so the window
            // draws itself instead: the same layout, without the frame.
            try
            {
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
