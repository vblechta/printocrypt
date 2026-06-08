using System.Diagnostics;
using System.Windows;
using Microsoft.Win32;
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
        var converter = new PostScriptConverter(_settings.GhostscriptPath);
        if (!converter.IsGhostscriptAvailable())
        {
            MessageBox.Show(
                "Ghostscript was not found. Install it from https://ghostscript.com/releases/gsdnld.html " +
                "or set the path in PrintoCrypt Settings.\n\nPrint jobs will fail until Ghostscript is available.",
                "PrintoCrypt",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
        }

        _trayIcon = new TrayIconService(this);
        _jobCoordinator = CreateJobCoordinator(_settings);

        var spoolDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "PrintoCrypt",
            "spool");

        _printServer = new PrintServer(_settings.ListenPort, spoolDir);
        _printServer.JobReceived += OnJobReceived;
        _printServer.Start();

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

        var spoolDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "PrintoCrypt",
            "spool");

        _printServer = new PrintServer(settings.ListenPort, spoolDir);
        _printServer.JobReceived += OnJobReceived;
        _printServer.Start();
    }

    private JobCoordinator CreateJobCoordinator(AppSettings settings)
    {
        var coordinator = new JobCoordinator(
            new PrintJobProcessor(new PostScriptConverter(settings.GhostscriptPath), new PdfEncryptionService()),
            settings);

        coordinator.JobCompleted += (_, path) =>
            _trayIcon?.ShowBalloon("Print saved", Path.GetFileName(path), Hardcodet.Wpf.TaskbarNotification.BalloonIcon.Info);

        coordinator.JobCancelled += (_, title) =>
            _trayIcon?.ShowBalloon("Print cancelled", title, Hardcodet.Wpf.TaskbarNotification.BalloonIcon.Warning);

        coordinator.JobFailed += (_, tuple) =>
            _trayIcon?.ShowBalloon("Print failed", tuple.Error.Message, Hardcodet.Wpf.TaskbarNotification.BalloonIcon.Error);

        coordinator.OutlookOpenFailed += (_, message) =>
            _trayIcon?.ShowBalloon("Outlook", message, Hardcodet.Wpf.TaskbarNotification.BalloonIcon.Warning);

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

    private Task<string?> RequestPasswordAsync(PrintJobInfo job)
    {
        var tcs = new TaskCompletionSource<string?>();

        Application.Current.Dispatcher.Invoke(() =>
        {
            var dialog = new PasswordDialog(job)
            {
                Owner = _settingsWindow?.IsVisible == true ? _settingsWindow : null
            };

            var result = dialog.ShowDialog();
            tcs.SetResult(result == true ? dialog.Password : null);
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
