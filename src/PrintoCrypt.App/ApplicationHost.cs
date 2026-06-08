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
    private AppSettings _settings;
    private PrintServer? _printServer;
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
        StartPrintServer();

        if (_settings.StartWithWindows)
        {
            EnsureStartupRegistration(true);
        }
    }

    public void Shutdown()
    {
        _printServer?.Stop();
        _printServer?.Dispose();
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

            _settingsWindow = new MainWindow(_settings, SaveSettings, RestartPrintServer);
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

    private void RestartPrintServer(AppSettings settings)
    {
        _settings = settings;
        _printServer?.Stop();
        _printServer?.Dispose();
        _jobCoordinator = CreateJobCoordinator(settings);
        StartPrintServer();
    }

    private void StartPrintServer()
    {
        var spoolDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "PrintoCrypt",
            "spool");

        _printServer = new PrintServer(_settings.ListenPort, spoolDir);
        _printServer.JobReceived += OnJobReceived;
        _printServer.Start();
    }

    private JobCoordinator CreateJobCoordinator(AppSettings settings)
    {
        var coordinator = new JobCoordinator(
            new PrintJobProcessor(new WpfXpsToPdfConverter(), new PdfEncryptionService()),
            settings);

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

        using var key = Registry.CurrentUser.OpenSubKey(keyName, writable: true);
        if (key is null)
        {
            return;
        }

        if (enabled)
        {
            key.SetValue(valueName, $"\"{exePath}\"");
        }
        else
        {
            key.DeleteValue(valueName, throwOnMissingValue: false);
        }
    }
}
