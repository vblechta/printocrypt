namespace PrintoCrypt.Core.Models;

public sealed class PrintJobInfo
{
    public required string JobId { get; init; }
    public required string SourcePath { get; init; }
    public string? DocumentTitle { get; init; }
    public string? UserName { get; init; }
    public DateTime ReceivedAt { get; init; } = DateTime.Now;
}
