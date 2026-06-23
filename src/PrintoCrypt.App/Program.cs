using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Hosting.WindowsServices;
using PrintoCrypt.App.Services;
using System.Windows;

namespace PrintoCrypt.App;

public static class Program
{
    [STAThread]
    public static void Main(string[] args)
    {
        if (args.Any(arg => string.Equals(arg, "--broker", StringComparison.OrdinalIgnoreCase)))
        {
            if (OperatingSystem.IsWindows() && WindowsServiceHelpers.IsWindowsService())
            {
                Host.CreateDefaultBuilder(args)
                    .UseWindowsService(options => options.ServiceName = BrokerServiceControl.ServiceName)
                    .ConfigureServices(services => services.AddHostedService<PrintoCryptBrokerService>())
                    .Build()
                    .Run();
            }
            else
            {
                BrokerProgram.Run();
            }

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
