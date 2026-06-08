using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using Microsoft.Win32;
using PrintoCrypt.App.Localization;
using PrintoCrypt.App.Services;
using PrintoCrypt.Core.Models;

namespace PrintoCrypt.App.Views;

public partial class MainWindow : Window
{
    private readonly AppSettings _settings;
    private readonly Action<AppSettings> _saveSettings;
    private readonly Action<AppSettings> _restartServer;
    private readonly List<EmailTemplate> _emailTemplates = [];
    private bool _updatingTemplateFields;
    private bool _globalSettingsUnlocked;

    public MainWindow(AppSettings settings, Action<AppSettings> saveSettings, Action<AppSettings> restartServer)
    {
        InitializeComponent();
        ApplyLocalization();
        _settings = settings;
        _saveSettings = saveSettings;
        _restartServer = restartServer;
        LoadFields();

        if (AdminHelper.IsRunningAsAdministrator())
        {
            UnlockGlobalSettings();
        }
        else
        {
            UpdateGlobalSettingsVisibility();
        }
    }

    private void ApplyLocalization()
    {
        Title = L.Get("MainWindow_Title");
        TitleText.Text = L.Get("MainWindow_Title");
        SubtitleText.Text = L.Get("MainWindow_Subtitle");
        UserSettingsTabItem.Header = L.Get("UserSettingsTab");
        GlobalSettingsTabItem.Header = L.Get("GlobalSettingsTab");
        OutputFolderLabel.Text = L.Get("OutputFolder");
        BrowseButton.Content = L.Get("Browse");
        OpenOutlookCheckBox.Content = L.Get("OpenOutlook");
        OpenFolderCheckBox.Content = L.Get("OpenFolderAfterSave");
        UseEmailTemplatesCheckBox.Content = L.Get("UseEmailTemplates");
        EmailTemplatesLabel.Text = L.Get("EmailTemplates");
        EmailTemplatesHelpText.Text = L.Get("EmailTemplatesHelp");
        AddTemplateButton.Content = L.Get("AddTemplate");
        RemoveTemplateButton.Content = L.Get("RemoveTemplate");
        TemplateNameLabel.Text = L.Get("EmailTemplateName");
        DefaultTemplateCheckBox.Content = L.Get("EmailTemplateDefault");
        TemplateSubjectLabel.Text = L.Get("EmailTemplateSubject");
        TemplateBodyLabel.Text = L.Get("EmailTemplateBody");
        GlobalSettingsLockedTitle.Text = L.Get("GlobalSettingsLockedTitle");
        GlobalSettingsLockedText.Text = L.Get("GlobalSettingsLockedText");
        UnlockGlobalSettingsButton.Content = L.Get("UnlockGlobalSettings");
        GlobalSettingsDescriptionText.Text = L.Get("GlobalSettingsDescription");
        ListenPortLabel.Text = L.Get("ListenPort");
        StartupCheckBox.Content = L.Get("StartupWithWindows");
        PrinterSetupLabel.Text = L.Get("PrinterSetup");
        PrinterSetupDescriptionText.Text = L.Get("PrinterSetupDescription");
        InstallPrinterButton.Content = L.Get("InstallPrinter");
        UninstallPrinterButton.Content = L.Get("UninstallPrinter");
        CloseButton.Content = L.Get("Close");
        SaveButton.Content = L.Get("Save");
    }

    private void LoadFields()
    {
        OutputDirectoryBox.Text = _settings.OutputDirectory;
        ListenPortBox.Text = _settings.ListenPort.ToString();
        OpenOutlookCheckBox.IsChecked = _settings.OpenOutlookAfterSave;
        OpenFolderCheckBox.IsChecked = _settings.OpenOutputFolderAfterSave;
        StartupCheckBox.IsChecked = _settings.StartWithWindows;
        UseEmailTemplatesCheckBox.IsChecked = _settings.UseEmailTemplates;

        _emailTemplates.Clear();
        _emailTemplates.AddRange(_settings.EmailTemplates.Select(CloneTemplate));
        RefreshTemplatesList();
        UpdateEmailTemplatesPanelVisibility();
    }

    private void SettingsTabs_OnSelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (e.Source != SettingsTabs)
        {
            return;
        }

        if (SettingsTabs.SelectedItem != GlobalSettingsTabItem || _globalSettingsUnlocked)
        {
            return;
        }

        if (AdminHelper.PromptForAdministratorApproval())
        {
            UnlockGlobalSettings();
            return;
        }

        UpdateGlobalSettingsVisibility();
    }

    private void UpdateGlobalSettingsVisibility()
    {
        if (SettingsTabs.SelectedItem != GlobalSettingsTabItem)
        {
            return;
        }

        if (_globalSettingsUnlocked)
        {
            GlobalSettingsLockedPanel.Visibility = Visibility.Collapsed;
            GlobalSettingsContent.Visibility = Visibility.Visible;
            return;
        }

        GlobalSettingsLockedPanel.Visibility = Visibility.Visible;
        GlobalSettingsContent.Visibility = Visibility.Collapsed;
    }

    private void UnlockGlobalSettings_OnClick(object sender, RoutedEventArgs e)
    {
        TryUnlockGlobalSettings();
    }

    private bool TryUnlockGlobalSettings()
    {
        if (_globalSettingsUnlocked)
        {
            return true;
        }

        if (!AdminHelper.PromptForAdministratorApproval())
        {
            MessageBox.Show(
                L.Get("AdminApprovalCancelled"),
                L.Get("AppTitle"),
                MessageBoxButton.OK,
                MessageBoxImage.Information);
            return false;
        }

        UnlockGlobalSettings();
        return true;
    }

    private void UnlockGlobalSettings()
    {
        _globalSettingsUnlocked = true;
        GlobalSettingsLockedPanel.Visibility = Visibility.Collapsed;
        GlobalSettingsContent.Visibility = Visibility.Visible;
    }

    private void RefreshTemplatesList()
    {
        var selectedId = (TemplatesListBox.SelectedItem as EmailTemplate)?.Id;
        TemplatesListBox.ItemsSource = null;
        TemplatesListBox.ItemsSource = _emailTemplates;

        if (selectedId is not null)
        {
            TemplatesListBox.SelectedItem = _emailTemplates.FirstOrDefault(t => t.Id == selectedId);
        }
        else if (_emailTemplates.Count > 0)
        {
            TemplatesListBox.SelectedIndex = 0;
        }

        UpdateTemplateEditorState();
    }

    private void UpdateEmailTemplatesPanelVisibility()
    {
        EmailTemplatesPanel.Visibility = UseEmailTemplatesCheckBox.IsChecked == true
            ? Visibility.Visible
            : Visibility.Collapsed;
    }

    private void UpdateTemplateEditorState()
    {
        var hasSelection = TemplatesListBox.SelectedItem is EmailTemplate;
        TemplateNameBox.IsEnabled = hasSelection;
        DefaultTemplateCheckBox.IsEnabled = hasSelection;
        TemplateSubjectBox.IsEnabled = hasSelection;
        TemplateBodyBox.IsEnabled = hasSelection;
        RemoveTemplateButton.IsEnabled = hasSelection;

        if (!hasSelection)
        {
            _updatingTemplateFields = true;
            TemplateNameBox.Text = string.Empty;
            DefaultTemplateCheckBox.IsChecked = false;
            TemplateSubjectBox.Text = string.Empty;
            TemplateBodyBox.Text = string.Empty;
            _updatingTemplateFields = false;
        }
    }

    private void LoadSelectedTemplateIntoEditor()
    {
        if (TemplatesListBox.SelectedItem is not EmailTemplate template)
        {
            UpdateTemplateEditorState();
            return;
        }

        _updatingTemplateFields = true;
        TemplateNameBox.Text = template.Name;
        DefaultTemplateCheckBox.IsChecked = template.IsDefault;
        TemplateSubjectBox.Text = template.Subject;
        TemplateBodyBox.Text = template.Body;
        _updatingTemplateFields = false;
        UpdateTemplateEditorState();
    }

    private AppSettings ReadFields()
    {
        var port = _settings.ListenPort;
        var startWithWindows = _settings.StartWithWindows;

        if (_globalSettingsUnlocked)
        {
            if (!int.TryParse(ListenPortBox.Text, out port) || port is < 1024 or > 65535)
            {
                throw new InvalidOperationException(L.Get("InvalidListenPort"));
            }

            startWithWindows = StartupCheckBox.IsChecked == true;
        }

        return new AppSettings
        {
            ListenPort = port,
            OutputDirectory = OutputDirectoryBox.Text.Trim(),
            OpenOutlookAfterSave = OpenOutlookCheckBox.IsChecked == true,
            OpenOutputFolderAfterSave = OpenFolderCheckBox.IsChecked == true,
            StartWithWindows = startWithWindows,
            UseEmailTemplates = UseEmailTemplatesCheckBox.IsChecked == true,
            EmailTemplates = _emailTemplates.Select(CloneTemplate).ToList(),
            PrinterName = _settings.PrinterName
        };
    }

    private void Save_OnClick(object sender, RoutedEventArgs e)
    {
        try
        {
            if (SettingsTabs.SelectedItem == GlobalSettingsTabItem && !_globalSettingsUnlocked)
            {
                MessageBox.Show(
                    L.Get("GlobalSettingsLockedText"),
                    L.Get("AppTitle"),
                    MessageBoxButton.OK,
                    MessageBoxImage.Warning);
                return;
            }

            var updated = ReadFields();
            Directory.CreateDirectory(updated.OutputDirectory);
            _saveSettings(updated);
            _restartServer(updated);
            MessageBox.Show(L.Get("SettingsSaved"), L.Get("AppTitle"), MessageBoxButton.OK, MessageBoxImage.Information);
        }
        catch (Exception ex)
        {
            MessageBox.Show(ex.Message, L.Get("AppTitle"), MessageBoxButton.OK, MessageBoxImage.Error);
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

    private void InstallPrinter_OnClick(object sender, RoutedEventArgs e)
    {
        if (!_globalSettingsUnlocked)
        {
            return;
        }

        RunScript("Install.ps1", L.Get("InstallPrinterAction"), "-PrinterOnly");
    }

    private void UninstallPrinter_OnClick(object sender, RoutedEventArgs e)
    {
        if (!_globalSettingsUnlocked)
        {
            return;
        }

        RunScript("Uninstall.ps1", L.Get("UninstallPrinterAction"), "-PrinterOnly");
    }

    private void UseEmailTemplatesCheckBox_OnChanged(object sender, RoutedEventArgs e)
    {
        UpdateEmailTemplatesPanelVisibility();
    }

    private void TemplatesListBox_OnSelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        LoadSelectedTemplateIntoEditor();
    }

    private void AddTemplate_OnClick(object sender, RoutedEventArgs e)
    {
        var template = new EmailTemplate
        {
            Name = L.Format("NewTemplateName", _emailTemplates.Count + 1),
            Subject = "{DocumentTitle}",
            Body = string.Empty
        };

        _emailTemplates.Add(template);
        RefreshTemplatesList();
        TemplatesListBox.SelectedItem = template;
    }

    private void RemoveTemplate_OnClick(object sender, RoutedEventArgs e)
    {
        if (TemplatesListBox.SelectedItem is not EmailTemplate template)
        {
            return;
        }

        _emailTemplates.RemoveAll(t => t.Id == template.Id);
        RefreshTemplatesList();
    }

    private void DefaultTemplateCheckBox_OnChanged(object sender, RoutedEventArgs e)
    {
        if (_updatingTemplateFields || TemplatesListBox.SelectedItem is not EmailTemplate template)
        {
            return;
        }

        if (DefaultTemplateCheckBox.IsChecked == true)
        {
            foreach (var item in _emailTemplates)
            {
                item.IsDefault = item.Id == template.Id;
            }
        }
        else
        {
            template.IsDefault = false;
        }

        RefreshTemplatesList();
        TemplatesListBox.SelectedItem = template;
    }

    private void TemplateField_OnTextChanged(object sender, TextChangedEventArgs e)
    {
        if (_updatingTemplateFields || TemplatesListBox.SelectedItem is not EmailTemplate template)
        {
            return;
        }

        template.Name = TemplateNameBox.Text;
        template.Subject = TemplateSubjectBox.Text;
        template.Body = TemplateBodyBox.Text;
        System.Windows.Data.CollectionViewSource.GetDefaultView(_emailTemplates)?.Refresh();
    }

    private void RunScript(string scriptName, string actionTitle, string? extraArguments = null)
    {
        if (!_globalSettingsUnlocked)
        {
            return;
        }

        var repoScript = FindScript(scriptName);
        if (repoScript is null)
        {
            MessageBox.Show(
                L.Format("ScriptNotFound", scriptName),
                L.Get("AppTitle"),
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
            return;
        }

        if (!int.TryParse(ListenPortBox.Text.Trim(), out var port) || port is < 1024 or > 65535)
        {
            MessageBox.Show(
                L.Get("SaveValidPortBeforeInstall"),
                L.Get("AppTitle"),
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
            return;
        }

        var resultFile = Path.Combine(Path.GetTempPath(), $"PrintoCrypt-{Guid.NewGuid():N}.json");

        try
        {
            using var process = Process.Start(new ProcessStartInfo
            {
                FileName = "powershell.exe",
                Arguments =
                    $"-NoProfile -ExecutionPolicy Bypass -File \"{repoScript}\" {extraArguments} -Port {port} -ResultFile \"{resultFile}\"",
                Verb = "runas",
                UseShellExecute = true
            });

            if (process is null)
            {
                MessageBox.Show(
                    L.Get("PrinterInstallCancelled"),
                    L.Get("AppTitle"),
                    MessageBoxButton.OK,
                    MessageBoxImage.Warning);
                return;
            }

            var deadline = DateTime.UtcNow.AddMinutes(2);
            while (DateTime.UtcNow < deadline && !File.Exists(resultFile))
            {
                if (process.HasExited)
                {
                    break;
                }

                Thread.Sleep(200);
            }

            var exitCode = process.HasExited ? process.ExitCode : -1;

            if (File.Exists(resultFile))
            {
                var json = File.ReadAllText(resultFile);
                using var document = System.Text.Json.JsonDocument.Parse(json);
                var root = document.RootElement;
                var success = root.TryGetProperty("success", out var successElement) && successElement.GetBoolean();
                var message = root.TryGetProperty("message", out var messageElement)
                    ? messageElement.GetString() ?? actionTitle
                    : actionTitle;

                MessageBox.Show(
                    message,
                    L.Get("AppTitle"),
                    MessageBoxButton.OK,
                    success ? MessageBoxImage.Information : MessageBoxImage.Error);
            }
            else if (exitCode == 0)
            {
                MessageBox.Show(
                    L.Format("ActionCompleted", actionTitle),
                    L.Get("AppTitle"),
                    MessageBoxButton.OK,
                    MessageBoxImage.Information);
            }
            else
            {
                MessageBox.Show(
                    L.Format("ActionFailed", actionTitle, exitCode, repoScript, port),
                    L.Get("AppTitle"),
                    MessageBoxButton.OK,
                    MessageBoxImage.Error);
            }
        }
        catch (System.ComponentModel.Win32Exception ex) when (ex.NativeErrorCode == 1223)
        {
            MessageBox.Show(
                L.Get("AdminApprovalCancelled"),
                L.Get("AppTitle"),
                MessageBoxButton.OK,
                MessageBoxImage.Information);
        }
        catch (Exception ex)
        {
            MessageBox.Show(ex.Message, L.Get("AppTitle"), MessageBoxButton.OK, MessageBoxImage.Error);
        }
        finally
        {
            try
            {
                if (File.Exists(resultFile))
                {
                    File.Delete(resultFile);
                }
            }
            catch
            {
            }
        }
    }

    private static EmailTemplate CloneTemplate(EmailTemplate template) => new()
    {
        Id = template.Id,
        Name = template.Name,
        Subject = template.Subject,
        Body = template.Body,
        IsDefault = template.IsDefault
    };

    private static string? FindScript(string scriptName)
    {
        var dir = AppContext.BaseDirectory;
        for (var i = 0; i < 6; i++)
        {
            foreach (var relativePath in new[] { scriptName, Path.Combine("scripts", scriptName) })
            {
                var candidate = Path.Combine(dir, relativePath);
                if (File.Exists(candidate))
                {
                    return candidate;
                }
            }

            dir = Path.GetFullPath(Path.Combine(dir, ".."));
        }

        return null;
    }
}
