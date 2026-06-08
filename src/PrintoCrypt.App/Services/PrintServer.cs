using System.Net;
using System.Net.Sockets;
using System.Text;
using PrintoCrypt.Core.Models;

namespace PrintoCrypt.App.Services;

public sealed class PrintServer : IDisposable
{
    private readonly int _port;
    private readonly string _spoolDirectory;
    private TcpListener? _listener;
    private CancellationTokenSource? _cts;
    private Task? _acceptLoop;

    public event EventHandler<PrintJobInfo>? JobReceived;
    public event EventHandler<string>? StatusChanged;
    public event EventHandler<Exception>? ErrorOccurred;

    public bool IsRunning => _listener is not null;

    public PrintServer(int port, string spoolDirectory)
    {
        _port = port;
        _spoolDirectory = spoolDirectory;
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
        await using var _ = client;
        client.ReceiveTimeout = 120_000;

        var jobId = DateTime.Now.ToString("yyyyMMdd_HHmmss_fff");
        var jobPath = Path.Combine(_spoolDirectory, $"{jobId}.ps");

        await using var networkStream = client.GetStream();
        await using var fileStream = File.Create(jobPath);

        var headerBuffer = new MemoryStream();
        var buffer = new byte[8192];
        string? documentTitle = null;
        var headerParsed = false;

        while (!cancellationToken.IsCancellationRequested)
        {
            var read = await networkStream.ReadAsync(buffer, cancellationToken);
            if (read == 0)
            {
                break;
            }

            if (!headerParsed)
            {
                headerBuffer.Write(buffer, 0, read);
                var headerText = Encoding.ASCII.GetString(headerBuffer.GetBuffer(), 0, (int)headerBuffer.Length);
                if (headerText.Contains("@PJL", StringComparison.OrdinalIgnoreCase))
                {
                    documentTitle = ExtractPjlValue(headerText, "TITLE");
                    if (headerText.Contains("@PJL ENTER LANGUAGE", StringComparison.OrdinalIgnoreCase))
                    {
                        headerParsed = true;
                        var marker = "@PJL ENTER LANGUAGE";
                        var index = headerText.IndexOf(marker, StringComparison.OrdinalIgnoreCase);
                        var lineEnd = headerText.IndexOf('\n', index);
                        if (lineEnd >= 0 && lineEnd + 1 < headerBuffer.Length)
                        {
                            var payloadStart = lineEnd + 1;
                            var remaining = (int)headerBuffer.Length - payloadStart;
                            if (remaining > 0)
                            {
                                fileStream.Write(headerBuffer.GetBuffer(), payloadStart, remaining);
                            }

                            headerBuffer.SetLength(0);
                            continue;
                        }
                    }
                }
                else
                {
                    headerParsed = true;
                    fileStream.Write(headerBuffer.GetBuffer(), 0, (int)headerBuffer.Length);
                    headerBuffer.SetLength(0);
                    continue;
                }
            }
            else
            {
                await fileStream.WriteAsync(buffer.AsMemory(0, read), cancellationToken);
            }
        }

        await fileStream.FlushAsync(cancellationToken);

        if (fileStream.Length == 0)
        {
            File.Delete(jobPath);
            return;
        }

        var job = new PrintJobInfo
        {
            JobId = jobId,
            SourcePath = jobPath,
            DocumentTitle = documentTitle,
            UserName = Environment.UserName
        };

        JobReceived?.Invoke(this, job);
    }

    private static string? ExtractPjlValue(string header, string key)
    {
        foreach (var line in header.Split('\n', '\r'))
        {
            var trimmed = line.Trim();
            if (!trimmed.StartsWith("@PJL", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            var eq = trimmed.IndexOf('=');
            if (eq < 0)
            {
                continue;
            }

            var name = trimmed[4..eq].Trim();
            if (!name.Equals(key, StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            return trimmed[(eq + 1)..].Trim().Trim('"');
        }

        return null;
    }

    public void Dispose()
    {
        Stop();
        _cts?.Dispose();
    }
}
