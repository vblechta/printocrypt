namespace PrintoCrypt.Core.Models;

public sealed class AppSettings
{
    public const int DefaultListenPort = 9150;
    public const string DefaultPrinterName = "PrintoCrypt";

    public int ListenPort { get; set; } = DefaultListenPort;
    public string PrinterName { get; set; } = DefaultPrinterName;
    public string OutputDirectory { get; set; } =
        Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments),
            "PrintoCrypt");
    public string? GhostscriptPath { get; set; }
    public bool OpenOutputFolderAfterSave { get; set; } = false;
    public bool OpenOutlookAfterSave { get; set; } = true;
    public bool StartWithWindows { get; set; } = true;
}
