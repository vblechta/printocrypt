using System.Security.AccessControl;
using System.Security.Principal;
using PrintoCrypt.Core.Models;
using PrintoCrypt.Core.Services;

namespace PrintoCrypt.App.Services;

public sealed class BrokerHost : IDisposable
{
    private readonly MachineSettingsStore _machineSettingsStore = new();
    private MachineSettings _machineSettings;
    private PrintServer? _printServer;

    public BrokerHost()
    {
        _machineSettings = _machineSettingsStore.Load();
    }

    public void Start()
    {
        var spoolDirectory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
            "PrintoCrypt",
            "broker-spool");

        _printServer = new PrintServer(
            _machineSettings.ListenPort,
            spoolDirectory,
            () => PrintSpoolerUserResolver.ResolvePrintingUser(_machineSettings.PrinterName));
        _printServer.JobReceived += (_, job) => _ = DispatchJobAsync(job);
        _printServer.Start();
    }

    public void Shutdown()
    {
        _printServer?.Stop();
        _printServer?.Dispose();
        _printServer = null;
    }

    private async Task DispatchJobAsync(PrintJobInfo job)
    {
        try
        {
            var targetUser = job.UserName
                ?? PrintSpoolerUserResolver.GetInteractiveUserName()
                ?? Environment.UserName;

            var userSpoolDirectory = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
                "PrintoCrypt",
                "spool",
                PrintJobPipeNames.SanitizeUserName(targetUser));

            Directory.CreateDirectory(userSpoolDirectory);
            EnsureUserCanAccessDirectory(userSpoolDirectory, targetUser);

            var destinationPath = Path.Combine(userSpoolDirectory, Path.GetFileName(job.SourcePath));
            File.Copy(job.SourcePath, destinationPath, overwrite: true);

            var routedJob = new PrintJobInfo
            {
                JobId = job.JobId,
                SourcePath = destinationPath,
                DocumentTitle = job.DocumentTitle,
                UserName = targetUser,
                ReceivedAt = job.ReceivedAt
            };

            if (!await PrintJobPipeClient.SendJobAsync(routedJob, targetUser))
            {
                TryDelete(job.SourcePath);
                TryDelete(destinationPath);
            }
        }
        catch
        {
            TryDelete(job.SourcePath);
        }
    }

    private static void EnsureUserCanAccessDirectory(string directoryPath, string userName)
    {
        var sanitizedAccount = userName.Contains('\\') ? userName : $"{Environment.UserDomainName}\\{userName}";
        var directoryInfo = new DirectoryInfo(directoryPath);
        var security = directoryInfo.Exists
            ? directoryInfo.GetAccessControl()
            : new DirectorySecurity();

        try
        {
            var account = new NTAccount(sanitizedAccount);
            security.AddAccessRule(new FileSystemAccessRule(
                account,
                FileSystemRights.Modify | FileSystemRights.ReadAndExecute | FileSystemRights.ListDirectory,
                InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit,
                PropagationFlags.None,
                AccessControlType.Allow));
            directoryInfo.Create();
            directoryInfo.SetAccessControl(security);
        }
        catch
        {
            // Best effort; broker still runs as SYSTEM and can read the files.
        }
    }

    private static void TryDelete(string path)
    {
        try
        {
            if (File.Exists(path))
            {
                File.Delete(path);
            }
        }
        catch
        {
        }
    }

    public void Dispose()
    {
        Shutdown();
    }
}
