using System.Windows;

namespace PrintoCrypt.App;

public partial class App : Application
{
    private const string SingleInstanceMutexName = "PrintoCrypt_SingleInstance";

    private ApplicationHost? _host;
    private Mutex? _singleInstanceMutex;

    protected override void OnStartup(StartupEventArgs e)
    {
        Localization.LocalizationSetup.ApplySystemLanguage();

        _singleInstanceMutex = new Mutex(true, SingleInstanceMutexName, out var createdNew);
        if (!createdNew)
        {
            Shutdown();
            return;
        }

        base.OnStartup(e);
        _host = new ApplicationHost();
        _host.Start();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _host?.Shutdown();
        _singleInstanceMutex?.ReleaseMutex();
        _singleInstanceMutex?.Dispose();
        base.OnExit(e);
    }
}
