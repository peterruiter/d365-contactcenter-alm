using System.IO.Compression;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;

namespace CcAlmRunner;

// Hosts PowerShell 7 in-process and runs scripts/run-local.ps1 from the embedded runner files, so
// the exe behaves exactly like the script: same arguments, same output. Ctrl+C or closing the
// window ends it.
//
//   ContactCenterALM-LocalRunner.exe [-Profile <name>] [-Port <n>] [-NoBrowser]
//
// Without -Profile it asks for one, like Start-LocalRunner.cmd.
internal static class Program
{
    // Start, exit and crash lines only: what support needs when "it just closed" on someone's laptop.
    private static readonly string LogPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "CcAlm", "runner-exe.log");

    private static void Log(string line)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(LogPath)!);
            File.AppendAllText(LogPath, $"{DateTime.Now:yyyy-MM-dd HH:mm:ss} [{Environment.ProcessId}] {line}{Environment.NewLine}");
        }
        catch { /* logging must never take the runner down */ }
    }

    private static int Main(string[] args)
    {
        Log($"start {string.Join(' ', args)}");
        AppDomain.CurrentDomain.UnhandledException += (_, e) => Log($"unhandled: {e.ExceptionObject}");
        AppDomain.CurrentDomain.ProcessExit += (_, _) => Log($"exit code {Environment.ExitCode}");
        try
        {
            return Run(args);
        }
        catch (Exception ex)
        {
            Log($"failed: {ex}");
            WriteColor(ex is RuntimeException rex && rex.ErrorRecord is not null ? rex.ErrorRecord.ToString() : ex.Message, ConsoleColor.Red);
            PauseIfDoubleClicked();
            return 1;
        }
    }

    private static int Run(string[] args)
    {
        var (profile, port, noBrowser) = ParseArgs(args);
        var root = ExtractPayload();

        if (profile is null)
        {
            Console.Write("Profile name - one per client (Enter for 'default'): ");
            var typed = Console.ReadLine()?.Trim();
            profile = string.IsNullOrEmpty(typed) ? "default" : typed;
        }

        var iss = InitialSessionState.CreateDefault();
        // The runner's own scripts, extracted from this exe; a downloaded exe's files would
        // otherwise count as "from the internet" for the execution policy.
        iss.ExecutionPolicy = Microsoft.PowerShell.ExecutionPolicy.Bypass;
        using var runspace = RunspaceFactory.CreateRunspace(iss);
        runspace.Open();
        using var ps = PowerShell.Create(runspace);

        ps.AddCommand(Path.Combine(root, "scripts", "run-local.ps1"))
          .AddParameter("ProfileName", profile)
          .AddParameter("Port", port);
        if (noBrowser) ps.AddParameter("NoBrowser");

        // No PSHost here, so Write-Host arrives on the information stream; keep its colours.
        ps.Streams.Information.DataAdded += (s, e) =>
        {
            var rec = ((PSDataCollection<InformationRecord>)s!)[e.Index];
            var color = rec.MessageData is HostInformationMessage him ? him.ForegroundColor : null;
            WriteColor(rec.MessageData?.ToString() ?? "", color);
        };
        ps.Streams.Warning.DataAdded += (s, e) => WriteColor("WARNING: " + ((PSDataCollection<WarningRecord>)s!)[e.Index].Message, ConsoleColor.Yellow);
        ps.Streams.Error.DataAdded += (s, e) => WriteColor(((PSDataCollection<ErrorRecord>)s!)[e.Index].ToString(), ConsoleColor.Red);
        var output = new PSDataCollection<PSObject>();
        output.DataAdded += (s, e) => Console.WriteLine(output[e.Index]?.ToString());

        // Deliberately no Ctrl+C handler. Registering one (Console.CancelKeyPress or
        // PosixSignalRegistration) made the process die about a second after start whenever it was
        // launched from a Command Prompt, while it ran fine from PowerShell or by double-click.
        // Without one, Ctrl+C ends the process like closing the window does, and the OS frees the
        // port with it.
        ps.Invoke(null, output);

        if (ps.HadErrors)
        {
            PauseIfDoubleClicked();
            return 1;
        }
        return 0;
    }

    private static (string? Profile, int Port, bool NoBrowser) ParseArgs(string[] args)
    {
        string? profile = null;
        var port = 7171;
        var noBrowser = false;
        for (var i = 0; i < args.Length; i++)
        {
            var a = args[i].TrimStart('-', '/').ToLowerInvariant();
            switch (a)
            {
                case "profile" or "profilename" when i + 1 < args.Length:
                    profile = args[++i];
                    break;
                case "port" when i + 1 < args.Length && int.TryParse(args[i + 1], out var p):
                    port = p;
                    i++;
                    break;
                case "nobrowser":
                    noBrowser = true;
                    break;
                case "help" or "?" or "h":
                    Console.WriteLine("ContactCenterALM-LocalRunner.exe [-Profile <name>] [-Port <n>] [-NoBrowser]");
                    Environment.Exit(0);
                    break;
                default:
                    throw new ArgumentException($"Unknown argument '{args[i]}'. Use -Profile <name>, -Port <n>, -NoBrowser.");
            }
        }
        return (profile, port, noBrowser);
    }

    /// <summary>
    /// Unpacks the embedded runner files to %LOCALAPPDATA%\CcAlm\runtime\&lt;hash&gt; once per build,
    /// and removes the folders older builds left behind.
    /// </summary>
    private static string ExtractPayload()
    {
        using var payload = Assembly.GetExecutingAssembly().GetManifestResourceStream("payload.zip")
            ?? throw new InvalidOperationException("This exe has no runner files embedded. Rebuild it with scripts/build-runner-release.ps1.");
        using var buffer = new MemoryStream();
        payload.CopyTo(buffer);
        var hash = Convert.ToHexString(SHA256.HashData(buffer.ToArray()))[..12].ToLowerInvariant();

        var runtimeDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "CcAlm", "runtime");
        var target = Path.Combine(runtimeDir, hash);
        var marker = Path.Combine(target, ".complete");
        if (!File.Exists(marker))
        {
            if (Directory.Exists(target)) Directory.Delete(target, recursive: true);
            buffer.Position = 0;
            using (var zip = new ZipArchive(buffer, ZipArchiveMode.Read))
            {
                zip.ExtractToDirectory(target);
            }
            File.WriteAllText(marker, DateTime.UtcNow.ToString("o"));
        }

        foreach (var old in Directory.GetDirectories(runtimeDir).Where(d => !d.EndsWith(hash, StringComparison.OrdinalIgnoreCase)))
        {
            try { Directory.Delete(old, recursive: true); } catch { /* in use by another running copy */ }
        }
        return target;
    }

    private static void WriteColor(string text, ConsoleColor? color)
    {
        if (color is null)
        {
            Console.WriteLine(text);
            return;
        }
        var before = Console.ForegroundColor;
        Console.ForegroundColor = color.Value;
        Console.WriteLine(text);
        Console.ForegroundColor = before;
    }

    // Started by double-click, the console window is ours alone and closes on exit, taking any
    // error message with it. Started from a terminal, there are other processes on the console.
    [DllImport("kernel32.dll")]
    private static extern uint GetConsoleProcessList(uint[] processList, uint processCount);

    private static void PauseIfDoubleClicked()
    {
        try
        {
            if (GetConsoleProcessList(new uint[2], 2) <= 1)
            {
                Console.WriteLine("Press any key to close.");
                Console.ReadKey(intercept: true);
            }
        }
        catch { /* no console */ }
    }
}
