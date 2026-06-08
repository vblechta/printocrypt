using System.ComponentModel;
using System.Diagnostics;
using System.Security.Principal;

namespace PrintoCrypt.App.Services;

internal static class AdminHelper
{
    public static bool IsRunningAsAdministrator()
    {
        using var identity = WindowsIdentity.GetCurrent();
        var principal = new WindowsPrincipal(identity);
        return principal.IsInRole(WindowsBuiltInRole.Administrator);
    }

    public static bool PromptForAdministratorApproval()
    {
        if (IsRunningAsAdministrator())
        {
            return true;
        }

        try
        {
            using var process = Process.Start(new ProcessStartInfo
            {
                FileName = "powershell.exe",
                Arguments = "-NoProfile -WindowStyle Hidden -Command \"exit 0\"",
                Verb = "runas",
                UseShellExecute = true,
                WindowStyle = ProcessWindowStyle.Hidden
            });

            if (process is null)
            {
                return false;
            }

            process.WaitForExit(30_000);
            return process.ExitCode == 0;
        }
        catch (Win32Exception ex) when (ex.NativeErrorCode == 1223)
        {
            return false;
        }
    }
}
