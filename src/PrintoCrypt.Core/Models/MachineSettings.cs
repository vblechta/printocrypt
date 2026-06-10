namespace PrintoCrypt.Core.Models;

public sealed class MachineSettings
{
    public int ListenPort { get; set; } = AppSettings.DefaultListenPort;
    public string PrinterName { get; set; } = AppSettings.DefaultPrinterName;
}
