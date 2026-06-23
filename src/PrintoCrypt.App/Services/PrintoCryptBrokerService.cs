using Microsoft.Extensions.Hosting;

namespace PrintoCrypt.App.Services;

internal sealed class PrintoCryptBrokerService : BackgroundService
{
    private BrokerHost? _brokerHost;

    protected override Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _brokerHost = new BrokerHost();
        _brokerHost.Start();

        stoppingToken.Register(() => _brokerHost?.Shutdown());

        return Task.Delay(Timeout.InfiniteTimeSpan, stoppingToken);
    }

    public override void Dispose()
    {
        _brokerHost?.Dispose();
        base.Dispose();
    }
}
