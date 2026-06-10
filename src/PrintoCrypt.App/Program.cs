using System.Threading;
using System.Windows;
using PrintoCrypt.App.Services;

namespace PrintoCrypt.App;

public static class Program
{
    [STAThread]
    public static void Main(string[] args)
    {
        if (args.Any(arg => string.Equals(arg, "--broker", StringComparison.OrdinalIgnoreCase)))
        {
            BrokerProgram.Run();
            return;
        }

        var app = new App();
        app.InitializeComponent();
        app.Run();
    }
}

internal static class BrokerProgram
{
    private const string BrokerMutexName = @"Global\PrintoCrypt_Broker";

    public static void Run()
    {
        using var instanceMutex = new Mutex(true, BrokerMutexName, out var createdNew);
        if (!createdNew)
        {
            return;
        }

        using var broker = new BrokerHost();
        broker.Start();

        using var shutdownSignal = new ManualResetEvent(false);
        AppDomain.CurrentDomain.ProcessExit += (_, _) => shutdownSignal.Set();
        shutdownSignal.WaitOne();
    }
}
