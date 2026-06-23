using System.IO.Pipes;
using System.Security.Principal;
using PrintoCrypt.Core.Models;

namespace PrintoCrypt.App.Services;

internal static class PrintJobPipeClient
{
    public static Task<bool> SendJobAsync(
        PrintJobInfo job,
        string targetUserName,
        CancellationToken cancellationToken = default)
        => SendJobAsync(job, targetUserName, attemptCount: 5, connectTimeoutMs: 3000, cancellationToken);

    public static async Task<bool> SendJobAsync(
        PrintJobInfo job,
        string targetUserName,
        int attemptCount,
        int connectTimeoutMs,
        CancellationToken cancellationToken = default)
    {
        var pipeName = PrintJobPipeNames.GetJobPipeName(targetUserName);

        for (var attempt = 0; attempt < attemptCount; attempt++)
        {
            try
            {
                await using var pipe = new NamedPipeClientStream(
                    ".",
                    pipeName,
                    PipeDirection.Out,
                    PipeOptions.Asynchronous,
                    TokenImpersonationLevel.Impersonation);

                await pipe.ConnectAsync(connectTimeoutMs, cancellationToken);
                await PrintJobPipeProtocol.WriteJobAsync(pipe, job, cancellationToken);
                return true;
            }
            catch
            {
                if (attempt + 1 < attemptCount)
                {
                    await Task.Delay(500, cancellationToken);
                }
            }
        }

        return false;
    }
}
