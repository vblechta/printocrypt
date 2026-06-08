using PrintoCrypt.Core.Localization;
using PrintoCrypt.Core.Models;

namespace PrintoCrypt.Core.Services;

public sealed class PrintJobProcessor
{
    private readonly IPrintDocumentConverter _converter;
    private readonly PdfEncryptionService _encryption;

    public PrintJobProcessor(IPrintDocumentConverter converter, PdfEncryptionService encryption)
    {
        _converter = converter;
        _encryption = encryption;
    }

    public string Process(PrintJobInfo job, string password, string? outputDirectory)
    {
        var targetDirectory = outputDirectory
            ?? Path.Combine(Path.GetTempPath(), "PrintoCrypt");
        Directory.CreateDirectory(targetDirectory);

        var baseName = SanitizeFileName(job.DocumentTitle ?? $"Print_{job.JobId}");
        var outputPath = GetUniqueOutputPath(targetDirectory, baseName);
        var tempPdfPath = Path.Combine(Path.GetTempPath(), $"printocrypt_{job.JobId}.pdf");

        try
        {
            switch (DetectSourceKind(job.SourcePath))
            {
                case PrintSourceKind.Pdf:
                    _encryption.EncryptFile(job.SourcePath, outputPath, password);
                    return outputPath;

                case PrintSourceKind.PostScript:
                    throw new InvalidOperationException(M.Get("Error_PostScriptInsteadOfPdf"));

                case PrintSourceKind.Xps:
                default:
                    _converter.ConvertToPdf(job.SourcePath, tempPdfPath);
                    _encryption.EncryptFile(tempPdfPath, outputPath, password);
                    return outputPath;
            }
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

    private static PrintSourceKind DetectSourceKind(string path)
    {
        using var stream = File.OpenRead(path);
        Span<byte> header = stackalloc byte[8192];
        var read = stream.Read(header);
        if (read == 0)
        {
            return PrintSourceKind.Unknown;
        }

        if (ContainsPdfMarker(header[..read]))
        {
            return PrintSourceKind.Pdf;
        }

        var ascii = System.Text.Encoding.ASCII.GetString(header[..read]);
        if (ascii.Contains("%!PS", StringComparison.Ordinal))
        {
            return PrintSourceKind.PostScript;
        }

        if (read >= 2 && header[0] == (byte)'P' && header[1] == (byte)'K')
        {
            return PrintSourceKind.Xps;
        }

        return PrintSourceKind.Unknown;
    }

    private static bool ContainsPdfMarker(ReadOnlySpan<byte> data)
    {
        if (data.Length >= 4 &&
            data[0] == (byte)'%' &&
            data[1] == (byte)'P' &&
            data[2] == (byte)'D' &&
            data[3] == (byte)'F')
        {
            return true;
        }

        var text = System.Text.Encoding.ASCII.GetString(data);
        return text.Contains("%PDF-", StringComparison.Ordinal);
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

    private enum PrintSourceKind
    {
        Unknown,
        Pdf,
        Xps,
        PostScript
    }
}
