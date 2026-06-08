using PdfSharp.Pdf;
using PdfSharp.Pdf.IO;

namespace PrintoCrypt.Core.Services;

public sealed class PdfEncryptionService
{
    public void EncryptFile(string sourcePdfPath, string destinationPdfPath, string password)
    {
        if (string.IsNullOrWhiteSpace(password))
        {
            throw new ArgumentException("Password is required.", nameof(password));
        }

        using var document = PdfReader.Open(sourcePdfPath, PdfDocumentOpenMode.Modify);

        var security = document.SecuritySettings;
        security.UserPassword = password;
        security.OwnerPassword = password;
        security.PermitPrint = false;
        security.PermitFullQualityPrint = false;
        security.PermitModifyDocument = false;
        security.PermitExtractContent = false;
        security.PermitAnnotations = false;
        security.PermitFormsFill = false;
        security.PermitAssembleDocument = false;

        var directory = Path.GetDirectoryName(destinationPdfPath);
        if (!string.IsNullOrEmpty(directory))
        {
            Directory.CreateDirectory(directory);
        }

        document.Save(destinationPdfPath);
    }
}
