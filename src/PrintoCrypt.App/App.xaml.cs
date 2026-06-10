using System.Windows;

namespace PrintoCrypt.App;

public partial class App : Application
{
    private ApplicationHost? _host;
    private Mutex? _instanceMutex;

    protected override void OnStartup(StartupEventArgs e)
    {
        Localization.LocalizationSetup.ApplySystemLanguage();

        if (!TryAcquireUserInstance())
        {
            Shutdown();
            return;
        }

        base.OnStartup(e);
        _host = new ApplicationHost();
        _host.Start();
    }

    private bool TryAcquireUserInstance()
    {
        var mutexName = $@"Local\PrintoCrypt_{Environment.UserName}";
        _instanceMutex = new Mutex(true, mutexName, out var createdNew);
        return createdNew;
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _host?.Shutdown();

        if (_instanceMutex is not null)
        {
            try
            {
                _instanceMutex.ReleaseMutex();
            }
            catch
            {
            }

            _instanceMutex.Dispose();
        }

        base.OnExit(e);
    }
}
