using System.Windows;
using Hardcodet.Wpf.TaskbarNotification;
using PrintoCrypt.App.Views;

namespace PrintoCrypt.App.Services;

public sealed class TrayIconService : IDisposable
{
    private readonly TaskbarIcon _icon;
    private readonly ApplicationHost _host;

    public TrayIconService(ApplicationHost host)
    {
        _host = host;
        _icon = new TaskbarIcon
        {
            ToolTipText = "PrintoCrypt – encrypted PDF printer",
            Icon = System.Drawing.SystemIcons.Shield
        };

        _icon.TrayMouseDoubleClick += (_, _) => _host.ShowSettings();
        _icon.ContextMenu = BuildMenu();
    }

    public void ShowBalloon(string title, string message, BalloonIcon icon = BalloonIcon.Info)
    {
        _icon.ShowBalloonTip(title, message, icon);
    }

    private System.Windows.Controls.ContextMenu BuildMenu()
    {
        var menu = new System.Windows.Controls.ContextMenu();

        var settings = new System.Windows.Controls.MenuItem { Header = "Settings" };
        settings.Click += (_, _) => _host.ShowSettings();

        var openFolder = new System.Windows.Controls.MenuItem { Header = "Open output folder" };
        openFolder.Click += (_, _) => _host.OpenOutputFolder();

        var exit = new System.Windows.Controls.MenuItem { Header = "Exit" };
        exit.Click += (_, _) => _host.Shutdown();

        menu.Items.Add(settings);
        menu.Items.Add(openFolder);
        menu.Items.Add(new System.Windows.Controls.Separator());
        menu.Items.Add(exit);
        return menu;
    }

    public void Dispose()
    {
        _icon.Dispose();
    }
}
