using System.IO.Pipes;
using PrintoCrypt.Core.Models;

namespace PrintoCrypt.App.Services;

internal sealed class PrintJobPipeServer : IDisposable
{
    private readonly string _pipeName;
    private CancellationTokenSource? _cts;
    private Task? _acceptLoop;

    public event EventHandler<PrintJobInfo>? JobReceived;

    public PrintJobPipeServer(string userName)
    {
        _pipeName = PrintJobPipeNames.GetJobPipeName(userName);
    }

    public void Start()
    {
        if (_acceptLoop is not null)
        {
            return;
        }

        _cts = new CancellationTokenSource();
        _acceptLoop = Task.Run(() => AcceptLoopAsync(_cts.Token));
    }

    public void Stop()
    {
        _cts?.Cancel();
    }

    private async Task AcceptLoopAsync(CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            await using var pipe = NamedPipeServerStreamAcl.Create(
                _pipeName,
                PipeDirection.In,
                NamedPipeServerStream.MaxAllowedServerInstances,
                PipeTransmissionMode.Byte,
                PipeOptions.Asynchronous,
                inBufferSize: 0,
                outBufferSize: 0,
                pipeSecurity: PrintJobPipeProtocol.CreateUserPipeSecurity());

            try
            {
                await pipe.WaitForConnectionAsync(cancellationToken);
                var job = await PrintJobPipeProtocol.ReadJobAsync(pipe, cancellationToken);
                if (job is not null)
                {
                    JobReceived?.Invoke(this, job);
                }
            }
            catch (OperationCanceledException)
            {
                break;
            }
            catch
            {
                // Ignore malformed broker deliveries and continue listening.
            }
        }
    }

    public void Dispose()
    {
        Stop();
        _cts?.Dispose();
    }
}
