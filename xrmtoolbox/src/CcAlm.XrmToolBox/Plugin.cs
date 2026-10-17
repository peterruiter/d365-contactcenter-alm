using System.ComponentModel.Composition;
using XrmToolBox.Extensibility;
using XrmToolBox.Extensibility.Interfaces;

namespace CcAlm.XrmToolBox
{
    [Export(typeof(IXrmToolBoxPlugin)),
     ExportMetadata("Name", "Contact Center ALM"),
     ExportMetadata("Description", "Compare and move Dynamics 365 Contact Center configuration between environments: workstreams with their routing, queues, rulesets, templates and channels. Records are matched by name, never by GUID; every dependency is checked before anything runs; dry run, apply with a check afterwards, and rollback."),
     ExportMetadata("SmallImageBase64", Icons.Small),
     ExportMetadata("BigImageBase64", Icons.Big),
     ExportMetadata("BackgroundColor", "#0070AD"),
     ExportMetadata("PrimaryFontColor", "#FFFFFF"),
     ExportMetadata("SecondaryFontColor", "#E6F1F8")]
    public class Plugin : PluginBase, IGitHubPlugin, IHelpPlugin
    {
        public override IXrmToolBoxPluginControl GetControl() => new MainControl();

        public string RepositoryName => "d365-contactcenter-alm";
        public string UserName => "peterruiter";
        public string HelpUrl => "https://github.com/peterruiter/d365-contactcenter-alm/blob/master/docs/xrmtoolbox.md";
    }
}
