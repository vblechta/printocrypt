using System.Reflection;

namespace PrintoCrypt.App.Services;

internal static class AppVersion
{
    public static string GetDisplayVersion()
    {
        var assembly = Assembly.GetEntryAssembly() ?? Assembly.GetExecutingAssembly();
        var informationalVersion = assembly
            .GetCustomAttribute<AssemblyInformationalVersionAttribute>()
            ?.InformationalVersion;

        if (!string.IsNullOrWhiteSpace(informationalVersion))
        {
            return StripBuildMetadata(informationalVersion);
        }

        var version = assembly.GetName().Version?.ToString(3);
        return string.IsNullOrWhiteSpace(version) ? "unknown" : version;
    }

    public static string? GetChangelogPath()
    {
        var installDirectory = Path.GetDirectoryName(Environment.ProcessPath);
        if (string.IsNullOrWhiteSpace(installDirectory))
        {
            return null;
        }

        var changelogPath = Path.Combine(installDirectory, "CHANGELOG.md");
        return File.Exists(changelogPath) ? changelogPath : null;
    }

    public static string ReadChangelog()
    {
        var changelogPath = GetChangelogPath();
        if (changelogPath is null)
        {
            return string.Empty;
        }

        try
        {
            return File.ReadAllText(changelogPath);
        }
        catch
        {
            return string.Empty;
        }
    }

    private static string StripBuildMetadata(string version)
    {
        var plusIndex = version.IndexOf('+');
        return plusIndex >= 0 ? version[..plusIndex] : version;
    }
}
