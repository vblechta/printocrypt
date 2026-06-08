using Ghostscript.NET;
using Ghostscript.NET.Processor;

namespace PrintoCrypt.Core.Services;

public sealed class PostScriptConverter
{
    private readonly string? _ghostscriptPath;

    public PostScriptConverter(string? ghostscriptPath = null)
    {
        _ghostscriptPath = ghostscriptPath;
    }

    public void ConvertToPdf(string postScriptPath, string pdfPath)
    {
        if (!File.Exists(postScriptPath))
        {
            throw new FileNotFoundException("Print job file was not found.", postScriptPath);
        }

        var directory = Path.GetDirectoryName(pdfPath);
        if (!string.IsNullOrEmpty(directory))
        {
            Directory.CreateDirectory(directory);
        }

        var version = ResolveGhostscriptVersion();
        using var processor = new GhostscriptProcessor(version);

        var args = new List<string>
        {
            "-dNOPAUSE",
            "-dBATCH",
            "-dSAFER",
            "-sDEVICE=pdfwrite",
            "-dCompatibilityLevel=1.4",
            $"-sOutputFile={pdfPath}",
            postScriptPath
        };

        processor.Process(args.ToArray());
    }

    public bool IsGhostscriptAvailable()
    {
        try
        {
            ResolveGhostscriptVersion();
            return true;
        }
        catch
        {
            return false;
        }
    }

    private GhostscriptVersionInfo ResolveGhostscriptVersion()
    {
        if (!string.IsNullOrWhiteSpace(_ghostscriptPath))
        {
            if (!File.Exists(_ghostscriptPath))
            {
                throw new InvalidOperationException(
                    $"Ghostscript was not found at '{_ghostscriptPath}'. Install Ghostscript or update the path in Settings.");
            }

            return new GhostscriptVersionInfo(
                new Version(0, 0, 0),
                GhostscriptLicense.GPL,
                _ghostscriptPath,
                string.Empty);
        }

        var installed = GhostscriptVersionInfo.GetInstalledVersions();
        if (installed.Length == 0)
        {
            throw new InvalidOperationException(
                "Ghostscript is not installed. Download it from https://ghostscript.com/releases/gsdnld.html " +
                "or set a custom Ghostscript path in PrintoCrypt Settings.");
        }

        return installed.OrderByDescending(v => v.Version).First();
    }
}
