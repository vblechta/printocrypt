using System.Runtime.InteropServices;
using PrintoCrypt.Core.Localization;

namespace PrintoCrypt.App.Services;

public static class OutlookEmailService
{
    private const int OlMailItem = 0;
    private const int OlByValue = 1;

    public static void CreateDraftWithAttachment(
        string filePath,
        string? subject = null,
        string? body = null)
    {
        if (!File.Exists(filePath))
        {
            throw new FileNotFoundException(M.Get("Error_EncryptedPdfNotFound"), filePath);
        }

        var outlookType = Type.GetTypeFromProgID("Outlook.Application")
            ?? throw new InvalidOperationException(M.Get("Error_OutlookNotInstalled"));

        dynamic? outlook = null;
        dynamic? mail = null;

        try
        {
            outlook = Activator.CreateInstance(outlookType)!;
            mail = outlook.CreateItem(OlMailItem);
            mail.Subject = string.IsNullOrWhiteSpace(subject)
                ? Path.GetFileNameWithoutExtension(filePath)
                : subject;

            if (!string.IsNullOrWhiteSpace(body))
            {
                mail.Body = body;
            }

            mail.Attachments.Add(filePath, OlByValue, 1, Path.GetFileName(filePath));
            mail.Display(false);
        }
        finally
        {
            if (mail is not null)
            {
                Marshal.ReleaseComObject(mail);
            }

            if (outlook is not null)
            {
                Marshal.ReleaseComObject(outlook);
            }
        }
    }
}
