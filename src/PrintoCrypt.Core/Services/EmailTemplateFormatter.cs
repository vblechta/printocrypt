using PrintoCrypt.Core.Models;

namespace PrintoCrypt.Core.Services;

public static class EmailTemplateFormatter
{
    public static string Apply(string template, PrintJobInfo job, string displayName)
    {
        if (string.IsNullOrEmpty(template))
        {
            return template;
        }

        var fileName = displayName.EndsWith(".pdf", StringComparison.OrdinalIgnoreCase)
            ? displayName
            : $"{displayName}.pdf";

        return template
            .Replace("{DocumentTitle}", displayName, StringComparison.Ordinal)
            .Replace("{FileName}", fileName, StringComparison.Ordinal)
            .Replace("{Date}", job.ReceivedAt.ToString("d"), StringComparison.Ordinal)
            .Replace("{Time}", job.ReceivedAt.ToString("t"), StringComparison.Ordinal);
    }
}
