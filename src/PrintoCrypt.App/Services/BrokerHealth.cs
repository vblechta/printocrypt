using System.Net;
using System.Net.NetworkInformation;

namespace PrintoCrypt.App.Services;

internal static class BrokerHealth
{
    public static bool IsListeningOnLoopback(int port)
    {
        if (port <= 0)
        {
            return false;
        }

        try
        {
            return IPGlobalProperties.GetIPGlobalProperties()
                .GetActiveTcpListeners()
                .Any(endpoint =>
                    endpoint.Port == port &&
                    (IPAddress.IsLoopback(endpoint.Address) || endpoint.Address.Equals(IPAddress.Any)));
        }
        catch
        {
            return false;
        }
    }
}
