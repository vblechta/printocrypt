using System.IO.Pipes;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text.Json;
using PrintoCrypt.Core.Models;

namespace PrintoCrypt.App.Services;

internal static class PrintJobPipeProtocol
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    public static PipeSecurity CreateUserPipeSecurity()
    {
        var security = new PipeSecurity();
        security.AddAccessRule(new PipeAccessRule(
            new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null),
            PipeAccessRights.FullControl,
            AccessControlType.Allow));
        security.AddAccessRule(new PipeAccessRule(
            new SecurityIdentifier(WellKnownSidType.AuthenticatedUserSid, null),
            PipeAccessRights.ReadWrite | PipeAccessRights.CreateNewInstance,
            AccessControlType.Allow));
        security.AddAccessRule(new PipeAccessRule(
            WindowsIdentity.GetCurrent().User ?? throw new InvalidOperationException("Current user identity is unavailable."),
            PipeAccessRights.FullControl,
            AccessControlType.Allow));
        return security;
    }

    public static async Task WriteJobAsync(Stream stream, PrintJobInfo job, CancellationToken cancellationToken)
    {
        var payload = JsonSerializer.SerializeToUtf8Bytes(job, JsonOptions);
        var lengthBytes = BitConverter.GetBytes(payload.Length);
        await stream.WriteAsync(lengthBytes, cancellationToken);
        await stream.WriteAsync(payload, cancellationToken);
        await stream.FlushAsync(cancellationToken);
    }

    public static async Task<PrintJobInfo?> ReadJobAsync(Stream stream, CancellationToken cancellationToken)
    {
        var lengthBytes = new byte[sizeof(int)];
        await ReadExactAsync(stream, lengthBytes, cancellationToken);

        var length = BitConverter.ToInt32(lengthBytes, 0);
        if (length <= 0 || length > 64 * 1024 * 1024)
        {
            return null;
        }

        var payload = new byte[length];
        await ReadExactAsync(stream, payload, cancellationToken);
        return JsonSerializer.Deserialize<PrintJobInfo>(payload, JsonOptions);
    }

    private static async Task ReadExactAsync(Stream stream, byte[] buffer, CancellationToken cancellationToken)
    {
        var offset = 0;
        while (offset < buffer.Length)
        {
            var read = await stream.ReadAsync(buffer.AsMemory(offset, buffer.Length - offset), cancellationToken);
            if (read == 0)
            {
                throw new EndOfStreamException("Unexpected end of pipe stream.");
            }

            offset += read;
        }
    }
}
