namespace PrintoCrypt.App.Services;

internal static class UserAppLauncher
{
    private static readonly object SyncRoot = new();
    private static readonly Dictionary<string, DateTimeOffset> LastLaunchAttempts = new(StringComparer.OrdinalIgnoreCase);
    private static readonly TimeSpan LaunchCooldown = TimeSpan.FromSeconds(15);

    public static bool TryLaunchForUser(string userName)
    {
        if (string.IsNullOrWhiteSpace(userName))
        {
            return false;
        }

        lock (SyncRoot)
        {
            if (LastLaunchAttempts.TryGetValue(userName, out var lastLaunch) &&
                DateTimeOffset.UtcNow - lastLaunch < LaunchCooldown)
            {
                return false;
            }

            LastLaunchAttempts[userName] = DateTimeOffset.UtcNow;
        }

        var applicationPath = ResolveUserApplicationPath();
        if (string.IsNullOrWhiteSpace(applicationPath))
        {
            return false;
        }

        var workingDirectory = Path.GetDirectoryName(applicationPath);
        if (string.IsNullOrWhiteSpace(workingDirectory))
        {
            return false;
        }

        return UserSessionProcessLauncher.TryLaunchInUserSession(
            userName,
            applicationPath,
            workingDirectory);
    }

    private static string? ResolveUserApplicationPath()
    {
        var exePath = Environment.ProcessPath;
        if (string.IsNullOrWhiteSpace(exePath) || !File.Exists(exePath))
        {
            return null;
        }

        return exePath;
    }
}
