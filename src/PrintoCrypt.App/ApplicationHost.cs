using System.Diagnostics;
using System.Windows;
using Microsoft.Win32;
using PrintoCrypt.App.Localization;
using PrintoCrypt.App.Services;
using PrintoCrypt.App.Views;
using PrintoCrypt.Core.Models;
using PrintoCrypt.Core.Services;

namespace PrintoCrypt.App;

public sealed class ApplicationHost
{
    private readonly SettingsStore _settingsStore = new();
    private readonly MachineSettingsStore _machineSettingsStore = new();
    private AppSettings _settings;
    private PrintJobPipeServer? _printJobPipeServer;
    private JobCoordinator? _jobCoordinator;
    private TrayIconService? _trayIcon;
    private MainWindow? _settingsWindow;

    public ApplicationHost()
    {
        _settings = _settingsStore.Load();
        Directory.CreateDirectory(_settings.OutputDirectory);
    }

    public void Start()
    {
        _trayIcon = new TrayIconService(this);
        _jobCoordinator = CreateJobCoordinator(_settings);
        StartPrintJobPipeServer();
        WarnIfBrokerIsNotRunning();

        if (_settings.StartWithWindows)
        {
            EnsureStartupRegistration(true);
        }
    }

    public void Shutdown()
    {
        _printJobPipeServer?.Stop();
        _printJobPipeServer?.Dispose();
        _trayIcon?.Dispose();
        Application.Current.Shutdown();
    }

    public void ShowSettings()
    {
        Application.Current.Dispatcher.Invoke(() =>
        {
            if (_settingsWindow is { IsVisible: true })
            {
                _settingsWindow.Activate();
                return;
            }

            _settingsWindow = new MainWindow(_settings, SaveSettings, ApplyMachineSettings);
            _settingsWindow.Show();
            _settingsWindow.Closed += (_, _) => _settingsWindow = null;
        });
    }

    public void OpenOutputFolder()
    {
        Directory.CreateDirectory(_settings.OutputDirectory);
        Process.Start(new ProcessStartInfo
        {
            FileName = _settings.OutputDirectory,
            UseShellExecute = true
        });
    }

    private void SaveSettings(AppSettings settings)
    {
        _settings = settings;
        _settingsStore.Save(settings);
        EnsureStartupRegistration(settings.StartWithWindows);
    }

    private void ApplyMachineSettings(AppSettings settings)
    {
        _settings = settings;
        _settingsStore.Save(settings);
        _machineSettingsStore.Save(new MachineSettings
        {
            ListenPort = settings.ListenPort,
            PrinterName = settings.PrinterName
        });
        RestartBrokerProcess();
    }

    private static void RestartBrokerProcess()
    {
        const string brokerTask = @"\PrintoCrypt\PrintoCrypt Broker";

        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = "schtasks.exe",
                Arguments = $"/End /TN \"{brokerTask}\"",
                UseShellExecute = false,
                CreateNoWindow = true
            })?.WaitForExit(3000);
        }
        catch
        {
        }

        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = "schtasks.exe",
                Arguments = $"/Run /TN \"{brokerTask}\"",
                UseShellExecute = false,
                CreateNoWindow = true
            })?.WaitForExit(5000);
        }
        catch
        {
        }
    }

    private void StartPrintJobPipeServer()
    {
        _printJobPipeServer = new PrintJobPipeServer(Environment.UserName);
        _printJobPipeServer.JobReceived += OnJobReceived;
        _printJobPipeServer.Start();
    }

    private void WarnIfBrokerIsNotRunning()
    {
        var machineSettings = _machineSettingsStore.Load();
        if (BrokerHealth.IsListeningOnLoopback(machineSettings.ListenPort))
        {
            return;
        }

        _trayIcon?.ShowBalloon(
            L.Get("Notification_BrokerTitle"),
            L.Get("Notification_BrokerNotRunning"),
            Hardcodet.Wpf.TaskbarNotification.BalloonIcon.Warning);
    }

    private JobCoordinator CreateJobCoordinator(AppSettings settings)
    {
        var coordinator = new JobCoordinator(
            new PrintJobProcessor(new WpfXpsToPdfConverter(), new PdfEncryptionService()),
            settings,
            new AnalyticsService());

        coordinator.JobCompleted += (_, info) =>
        {
            if (info.OutlookDraftOpened)
            {
                _trayIcon?.ShowBalloon(
                    L.Get("Notification_OutlookTitle"),
                    L.Format("Notification_OutlookDraftOpened", info.DisplayName),
                    Hardcodet.Wpf.TaskbarNotification.BalloonIcon.Info);
                return;
            }

            if (info.SavedPath is not null)
            {
                _trayIcon?.ShowBalloon(
                    L.Get("Notification_PrintSaved"),
                    Path.GetFileName(info.SavedPath),
                    Hardcodet.Wpf.TaskbarNotification.BalloonIcon.Info);
            }
        };

        coordinator.JobCancelled += (_, title) =>
            _trayIcon?.ShowBalloon(L.Get("Notification_PrintCancelled"), title, Hardcodet.Wpf.TaskbarNotification.BalloonIcon.Warning);

        coordinator.JobFailed += (_, tuple) =>
            _trayIcon?.ShowBalloon(L.Get("Notification_PrintFailed"), tuple.Error.Message, Hardcodet.Wpf.TaskbarNotification.BalloonIcon.Error);

        return coordinator;
    }

    private void OnJobReceived(object? sender, PrintJobInfo job)
    {
        Application.Current.Dispatcher.InvokeAsync(async () =>
        {
            if (_jobCoordinator is null)
            {
                return;
            }

            await _jobCoordinator.HandleJobAsync(job, RequestPasswordAsync);
        });
    }

    private Task<PasswordSubmission?> RequestPasswordAsync(PrintJobInfo job)
    {
        var tcs = new TaskCompletionSource<PasswordSubmission?>();

        Application.Current.Dispatcher.Invoke(() =>
        {
            var dialog = new PasswordDialog(job, _settings)
            {
                Owner = _settingsWindow?.IsVisible == true ? _settingsWindow : null
            };

            var result = dialog.ShowDialog();
            if (result == true)
            {
                tcs.SetResult(new PasswordSubmission
                {
                    Password = dialog.Password,
                    EmailTemplate = dialog.SelectedEmailTemplate
                });
            }
            else
            {
                tcs.SetResult(null);
            }
        });

        return tcs.Task;
    }

    private static void EnsureStartupRegistration(bool enabled)
    {
        const string keyName = @"Software\Microsoft\Windows\CurrentVersion\Run";
        const string valueName = "PrintoCrypt";
        var exePath = Environment.ProcessPath;

        if (string.IsNullOrWhiteSpace(exePath))
        {
            return;
        }

        var quotedPath = BuildStartupCommand(exePath);

        if (enabled)
        {
            SetRunValue(Registry.CurrentUser, keyName, valueName, quotedPath);

            if (AdminHelper.IsRunningAsAdministrator())
            {
                DeleteRunValue(Registry.LocalMachine, keyName, valueName);
            }
        }
        else
        {
            DeleteRunValue(Registry.CurrentUser, keyName, valueName);
        }
    }

    private static void SetRunValue(RegistryKey root, string keyName, string valueName, string value)
    {
        using var key = root.OpenSubKey(keyName, writable: true);
        key?.SetValue(valueName, value);
    }

    private static void DeleteRunValue(RegistryKey root, string keyName, string valueName)
    {
        using var key = root.OpenSubKey(keyName, writable: true);
        key?.DeleteValue(valueName, throwOnMissingValue: false);
    }

    private static string BuildStartupCommand(string exePath)
    {
        var installDir = Path.GetDirectoryName(exePath);
        if (string.IsNullOrWhiteSpace(installDir))
        {
            return $"\"{exePath}\"";
        }

        return $"powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command \"Start-Process -LiteralPath '{exePath.Replace("'", "''")}' -WorkingDirectory '{installDir.Replace("'", "''")}'\"";
    }
}
