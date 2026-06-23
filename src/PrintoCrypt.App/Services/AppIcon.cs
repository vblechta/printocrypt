using System.Drawing;

namespace PrintoCrypt.App.Services;

internal static class AppIcon
{
    public static Icon GetTrayIcon()
    {
        var processPath = Environment.ProcessPath;
        if (!string.IsNullOrWhiteSpace(processPath))
        {
            var associatedIcon = Icon.ExtractAssociatedIcon(processPath);
            if (associatedIcon is not null)
            {
                return associatedIcon;
            }
        }

        return SystemIcons.Application;
    }
}
