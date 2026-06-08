using System.Runtime.InteropServices;

namespace PrintoCrypt.App.Services;

public static class OutlookEmailService
{
    private const int OlMailItem = 0;

    public static void CreateDraftWithAttachment(string filePath, string? subject = null)
    {
        if (!File.Exists(filePath))
        {
            throw new FileNotFoundException("Encrypted PDF was not found.", filePath);
        }

        var outlookType = Type.GetTypeFromProgID("Outlook.Application")
            ?? throw new InvalidOperationException(
                "Microsoft Outlook is not installed or not registered on this computer.");

        dynamic? outlook = null;
        dynamic? mail = null;

        try
        {
            outlook = Activator.CreateInstance(outlookType)!;
            mail = outlook.CreateItem(OlMailItem);
            mail.Subject = string.IsNullOrWhiteSpace(subject)
                ? Path.GetFileNameWithoutExtension(filePath)
                : subject;
            mail.Attachments.Add(filePath);
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
