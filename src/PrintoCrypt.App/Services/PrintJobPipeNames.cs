using System.Text.RegularExpressions;

namespace PrintoCrypt.App.Services;

internal static partial class PrintJobPipeNames
{
    public static string GetJobPipeName(string userName)
        => $"PrintoCrypt.jobs.{SanitizeUserName(userName)}";

    public static string SanitizeUserName(string userName)
    {
        if (string.IsNullOrWhiteSpace(userName))
        {
            return "unknown";
        }

        var withoutDomain = userName.Contains('\\')
            ? userName[(userName.LastIndexOf('\\') + 1)..]
            : userName;

        return SanitizeRegex().Replace(withoutDomain, "_");
    }

    [GeneratedRegex(@"[^\w\-\.]")]
    private static partial Regex SanitizeRegex();
}
