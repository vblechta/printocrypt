using System.Windows;
using PrintoCrypt.App.Localization;
using PrintoCrypt.App.Services;

namespace PrintoCrypt.App.Views;

public partial class ChangelogWindow : Window
{
    public ChangelogWindow(Window? owner)
    {
        InitializeComponent();
        Owner = owner;
        ApplyLocalization();
        LoadChangelog();
    }

    private void ApplyLocalization()
    {
        Title = L.Get("Changelog_Title");
        CloseButton.Content = L.Get("Close");
    }

    private void LoadChangelog()
    {
        var changelog = AppVersion.ReadChangelog();
        ChangelogText.Text = string.IsNullOrWhiteSpace(changelog)
            ? L.Get("Changelog_NotFound")
            : changelog;
    }

    private void CloseButton_OnClick(object sender, RoutedEventArgs e) => Close();
}
