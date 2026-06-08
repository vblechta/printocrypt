using PrintoCrypt.Core.Models;

namespace PrintoCrypt.Core.Services;

public sealed class PrintJobProcessor
{
    private readonly PostScriptConverter _converter;
    private readonly PdfEncryptionService _encryption;

    public PrintJobProcessor(PostScriptConverter converter, PdfEncryptionService encryption)
    {
        _converter = converter;
        _encryption = encryption;
    }

    public string Process(PrintJobInfo job, string password, string outputDirectory)
    {
        Directory.CreateDirectory(outputDirectory);

        var baseName = SanitizeFileName(job.DocumentTitle ?? $"Print_{job.JobId}");
        var tempPdfPath = Path.Combine(Path.GetTempPath(), $"printocrypt_{job.JobId}.pdf");
        var outputPath = GetUniqueOutputPath(outputDirectory, baseName);

        try
        {
            _converter.ConvertToPdf(job.SourcePath, tempPdfPath);
            _encryption.EncryptFile(tempPdfPath, outputPath, password);
            return outputPath;
        }
        finally
        {
            if (File.Exists(tempPdfPath))
            {
                try { File.Delete(tempPdfPath); } catch { /* best effort */ }
            }

            if (File.Exists(job.SourcePath))
            {
                try { File.Delete(job.SourcePath); } catch { /* best effort */ }
            }
        }
    }

    private static string GetUniqueOutputPath(string outputDirectory, string baseName)
    {
        var candidate = Path.Combine(outputDirectory, $"{baseName}.pdf");
        if (!File.Exists(candidate))
        {
            return candidate;
        }

        for (var i = 1; i < 1000; i++)
        {
            candidate = Path.Combine(outputDirectory, $"{baseName}_{i}.pdf");
            if (!File.Exists(candidate))
            {
                return candidate;
            }
        }

        return Path.Combine(outputDirectory, $"{baseName}_{Guid.NewGuid():N}.pdf");
    }

    private static string SanitizeFileName(string name)
    {
        var invalid = Path.GetInvalidFileNameChars();
        var cleaned = new string(name.Select(ch => invalid.Contains(ch) ? '_' : ch).ToArray()).Trim();
        if (string.IsNullOrWhiteSpace(cleaned))
        {
            return "Document";
        }

        return cleaned.Length > 80 ? cleaned[..80] : cleaned;
    }
}
