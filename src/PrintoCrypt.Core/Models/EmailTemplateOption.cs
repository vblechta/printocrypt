namespace PrintoCrypt.Core.Models;

public sealed class EmailTemplateOption
{
    public EmailTemplate? Template { get; init; }
    public required string DisplayName { get; init; }
}
