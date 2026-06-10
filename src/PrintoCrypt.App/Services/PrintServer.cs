using System.Net;
using System.Net.Sockets;
using PrintoCrypt.Core.Models;

namespace PrintoCrypt.App.Services;

public sealed class PrintServer : IDisposable
{
    private readonly int _port;
    private readonly string _spoolDirectory;
    private readonly Func<string?>? _resolvePrintingUser;
    private TcpListener? _listener;
    private CancellationTokenSource? _cts;
    private Task? _acceptLoop;

    public event EventHandler<PrintJobInfo>? JobReceived;
    public event EventHandler<string>? StatusChanged;
    public event EventHandler<Exception>? ErrorOccurred;

    public bool IsRunning => _listener is not null;

    public PrintServer(int port, string spoolDirectory, Func<string?>? resolvePrintingUser = null)
    {
        _port = port;
        _spoolDirectory = spoolDirectory;
        _resolvePrintingUser = resolvePrintingUser;
        Directory.CreateDirectory(_spoolDirectory);
    }

    public void Start()
    {
        if (IsRunning)
        {
            return;
        }

        _cts = new CancellationTokenSource();
        _listener = new TcpListener(IPAddress.Loopback, _port);
        _listener.Start();
        StatusChanged?.Invoke(this, $"Listening on 127.0.0.1:{_port}");
        _acceptLoop = Task.Run(() => AcceptLoopAsync(_cts.Token));
    }

    public void Stop()
    {
        _cts?.Cancel();
        _listener?.Stop();
        _listener = null;
    }

    private async Task AcceptLoopAsync(CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested && _listener is not null)
        {
            try
            {
                var client = await _listener.AcceptTcpClientAsync(cancellationToken);
                _ = Task.Run(() => HandleClientAsync(client, cancellationToken), cancellationToken);
            }
            catch (OperationCanceledException)
            {
                break;
            }
            catch (Exception ex)
            {
                ErrorOccurred?.Invoke(this, ex);
            }
        }
    }

    private async Task HandleClientAsync(TcpClient client, CancellationToken cancellationToken)
    {
        using (client)
        {
            client.ReceiveTimeout = 120_000;
            var resolvedUser = _resolvePrintingUser?.Invoke();

            var jobId = DateTime.Now.ToString("yyyyMMdd_HHmmss_fff");
            var jobPath = Path.Combine(_spoolDirectory, $"{jobId}.job");

            await using var networkStream = client.GetStream();
            using var rawJobStream = new MemoryStream();
            await networkStream.CopyToAsync(rawJobStream, cancellationToken);

            if (rawJobStream.Length == 0)
            {
                return;
            }

            var rawJob = rawJobStream.ToArray();
            var (payload, documentTitle) = PrintJobPayloadNormalizer.ExtractPrintPayload(rawJob);
            var normalized = PrintJobPayloadNormalizer.NormalizeBytes(payload.Length > 0 ? payload : rawJob);

            await File.WriteAllBytesAsync(jobPath, normalized, cancellationToken);

            var job = new PrintJobInfo
            {
                JobId = jobId,
                SourcePath = jobPath,
                DocumentTitle = documentTitle,
                UserName = resolvedUser ?? Environment.UserName
            };

            JobReceived?.Invoke(this, job);
        }
    }

    public void Dispose()
    {
        Stop();
        _cts?.Dispose();
    }
}
