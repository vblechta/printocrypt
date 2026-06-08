namespace PrintoCrypt.Core.Services;

public interface IPrintDocumentConverter
{
    void ConvertToPdf(string sourcePath, string pdfPath);
}
