namespace PrintoCrypt.Core.Models;

public sealed class PasswordSubmission
{
    public required string Password { get; init; }
    public EmailTemplate? EmailTemplate { get; init; }
}
