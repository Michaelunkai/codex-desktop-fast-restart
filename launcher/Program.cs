using System;
using System.Diagnostics;
using System.IO;
using System.Text;

internal static class Program
{
    private static int Main(string[] args)
    {
        var baseDirectory = AppDomain.CurrentDomain.BaseDirectory;
        var scriptPath = Path.Combine(baseDirectory, "scripts", "Restart-CodexDesktopFast.ps1");

        if (!File.Exists(scriptPath))
        {
            scriptPath = Path.GetFullPath(Path.Combine(baseDirectory, "..", "scripts", "Restart-CodexDesktopFast.ps1"));
        }

        if (!File.Exists(scriptPath))
        {
            return 2;
        }

        var powershellPath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.Windows),
            "System32",
            "WindowsPowerShell",
            "v1.0",
            "powershell.exe");

        var arguments = new StringBuilder();
        AppendArgument(arguments, "-NoProfile");
        AppendArgument(arguments, "-ExecutionPolicy");
        AppendArgument(arguments, "Bypass");
        AppendArgument(arguments, "-WindowStyle");
        AppendArgument(arguments, "Hidden");
        AppendArgument(arguments, "-File");
        AppendArgument(arguments, scriptPath);

        foreach (var arg in args)
        {
            AppendArgument(arguments, arg);
        }

        var startInfo = new ProcessStartInfo
        {
            FileName = powershellPath,
            Arguments = arguments.ToString(),
            UseShellExecute = false,
            CreateNoWindow = true,
            WorkingDirectory = baseDirectory
        };

        using (var process = Process.Start(startInfo))
        {
            if (process == null)
            {
                return 3;
            }

            return 0;
        }
    }

    private static void AppendArgument(StringBuilder builder, string value)
    {
        if (builder.Length > 0)
        {
            builder.Append(' ');
        }

        if (value.IndexOfAny(new[] { ' ', '\t', '"' }) < 0)
        {
            builder.Append(value);
            return;
        }

        builder.Append('"');
        var backslashes = 0;
        foreach (var ch in value)
        {
            if (ch == '\\')
            {
                backslashes++;
                continue;
            }

            if (ch == '"')
            {
                builder.Append('\\', backslashes * 2);
                builder.Append("\\\"");
                backslashes = 0;
                continue;
            }

            if (backslashes > 0)
            {
                builder.Append('\\', backslashes);
                backslashes = 0;
            }

            builder.Append(ch);
        }

        if (backslashes > 0)
        {
            builder.Append('\\', backslashes * 2);
        }

        builder.Append('"');
    }
}
