using System.IO.Pipes;
using System.Security.Principal;
using PrintoCrypt.Core.Models;

namespace PrintoCrypt.App.Services;

internal static class PrintJobPipeClient
{
    public static async Task<bool> SendJobAsync(PrintJobInfo job, string targetUserName, CancellationToken cancellationToken = default)
    {
        var pipeName = PrintJobPipeNames.GetJobPipeName(targetUserName);

        for (var attempt = 0; attempt < 5; attempt++)
        {
            try
            {
                await using var pipe = new NamedPipeClientStream(
                    ".",
                    pipeName,
                    PipeDirection.Out,
                    PipeOptions.Asynchronous,
                    TokenImpersonationLevel.Impersonation);

                await pipe.ConnectAsync(3000, cancellationToken);
                await PrintJobPipeProtocol.WriteJobAsync(pipe, job, cancellationToken);
                return true;
            }
            catch
            {
                await Task.Delay(500, cancellationToken);
            }
        }

        return false;
    }
}
