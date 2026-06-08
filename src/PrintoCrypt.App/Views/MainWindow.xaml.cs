using System.Diagnostics;
using System.IO;
using System.Windows;
using Microsoft.Win32;
using PrintoCrypt.Core.Models;

namespace PrintoCrypt.App.Views;

public partial class MainWindow : Window
{
    private readonly AppSettings _settings;
    private readonly Action<AppSettings> _saveSettings;
    private readonly Action<AppSettings> _restartServer;

    public MainWindow(AppSettings settings, Action<AppSettings> saveSettings, Action<AppSettings> restartServer)
    {
        InitializeComponent();
        _settings = settings;
        _saveSettings = saveSettings;
        _restartServer = restartServer;
        LoadFields();
    }

    private void LoadFields()
    {
        OutputDirectoryBox.Text = _settings.OutputDirectory;
        ListenPortBox.Text = _settings.ListenPort.ToString();
        GhostscriptPathBox.Text = _settings.GhostscriptPath ?? string.Empty;
        OpenOutlookCheckBox.IsChecked = _settings.OpenOutlookAfterSave;
        OpenFolderCheckBox.IsChecked = _settings.OpenOutputFolderAfterSave;
        StartupCheckBox.IsChecked = _settings.StartWithWindows;
    }

    private AppSettings ReadFields()
    {
        if (!int.TryParse(ListenPortBox.Text, out var port) || port is < 1024 or > 65535)
        {
            throw new InvalidOperationException("Listen port must be between 1024 and 65535.");
        }

        return new AppSettings
        {
            ListenPort = port,
            OutputDirectory = OutputDirectoryBox.Text.Trim(),
            GhostscriptPath = string.IsNullOrWhiteSpace(GhostscriptPathBox.Text)
                ? null
                : GhostscriptPathBox.Text.Trim(),
            OpenOutlookAfterSave = OpenOutlookCheckBox.IsChecked == true,
            OpenOutputFolderAfterSave = OpenFolderCheckBox.IsChecked == true,
            StartWithWindows = StartupCheckBox.IsChecked == true,
            PrinterName = _settings.PrinterName
        };
    }

    private void Save_OnClick(object sender, RoutedEventArgs e)
    {
        try
        {
            var updated = ReadFields();
            Directory.CreateDirectory(updated.OutputDirectory);
            _saveSettings(updated);
            _restartServer(updated);
            MessageBox.Show("Settings saved.", "PrintoCrypt", MessageBoxButton.OK, MessageBoxImage.Information);
        }
        catch (Exception ex)
        {
            MessageBox.Show(ex.Message, "PrintoCrypt", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void Close_OnClick(object sender, RoutedEventArgs e) => Close();

    private void BrowseOutputFolder_OnClick(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFolderDialog
        {
            InitialDirectory = OutputDirectoryBox.Text
        };

        if (dialog.ShowDialog() == true)
        {
            OutputDirectoryBox.Text = dialog.FolderName;
        }
    }

    private void BrowseGhostscript_OnClick(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog
        {
            Filter = "Ghostscript (gswin64c.exe;gswin32c.exe)|gswin64c.exe;gswin32c.exe|All files|*.*",
            Title = "Select Ghostscript executable"
        };

        if (dialog.ShowDialog() == true)
        {
            GhostscriptPathBox.Text = dialog.FileName;
        }
    }

    private void InstallPrinter_OnClick(object sender, RoutedEventArgs e)
    {
        RunScript("Install-Printer.ps1");
    }

    private void UninstallPrinter_OnClick(object sender, RoutedEventArgs e)
    {
        RunScript("Uninstall-Printer.ps1");
    }

    private void RunScript(string scriptName)
    {
        var repoScript = FindScript(scriptName);
        if (repoScript is null)
        {
            MessageBox.Show(
                $"Could not find {scriptName}. Run it manually from the scripts folder in the repository.",
                "PrintoCrypt",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
            return;
        }

        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = "powershell.exe",
                Arguments = $"-ExecutionPolicy Bypass -File \"{repoScript}\" -Port {ListenPortBox.Text.Trim()}",
                Verb = "runas",
                UseShellExecute = true
            });
        }
        catch (Exception ex)
        {
            MessageBox.Show(ex.Message, "PrintoCrypt", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private static string? FindScript(string scriptName)
    {
        var dir = AppContext.BaseDirectory;
        for (var i = 0; i < 6; i++)
        {
            var candidate = Path.Combine(dir, "scripts", scriptName);
            if (File.Exists(candidate))
            {
                return candidate;
            }

            dir = Path.GetFullPath(Path.Combine(dir, ".."));
        }

        return null;
    }
}
