using System.ServiceProcess;

namespace PrintoCrypt.App.Services;

internal static class BrokerServiceControl
{
    public const string ServiceName = "PrintoCryptBroker";

    public static bool IsInstalled()
    {
        try
        {
            using var service = new ServiceController(ServiceName);
            _ = service.Status;
            return true;
        }
        catch
        {
            return false;
        }
    }

    public static void EnsureRunning()
    {
        if (!IsInstalled())
        {
            return;
        }

        try
        {
            using var service = new ServiceController(ServiceName);
            if (service.Status is ServiceControllerStatus.Running or ServiceControllerStatus.StartPending)
            {
                if (service.Status == ServiceControllerStatus.StartPending)
                {
                    service.WaitForStatus(ServiceControllerStatus.Running, TimeSpan.FromSeconds(15));
                }

                return;
            }

            service.Start();
            service.WaitForStatus(ServiceControllerStatus.Running, TimeSpan.FromSeconds(15));
        }
        catch
        {
        }
    }

    public static void Restart()
    {
        if (!IsInstalled())
        {
            return;
        }

        try
        {
            using var service = new ServiceController(ServiceName);
            if (service.Status == ServiceControllerStatus.Running)
            {
                service.Stop();
                service.WaitForStatus(ServiceControllerStatus.Stopped, TimeSpan.FromSeconds(15));
            }

            service.Start();
            service.WaitForStatus(ServiceControllerStatus.Running, TimeSpan.FromSeconds(15));
        }
        catch
        {
        }
    }
}
