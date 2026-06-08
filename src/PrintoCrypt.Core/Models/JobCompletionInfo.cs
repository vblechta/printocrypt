namespace PrintoCrypt.Core.Models;

public sealed class JobCompletionInfo
{
    public string DisplayName { get; init; } = "Document";
    public string? SavedPath { get; init; }
    public bool OutlookDraftOpened { get; init; }
}
