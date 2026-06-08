using System.Windows;

namespace PrintoCrypt.App;

public partial class App : Application
{
    private ApplicationHost? _host;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        _host = new ApplicationHost();
        _host.Start();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _host?.Shutdown();
        base.OnExit(e);
    }
}
