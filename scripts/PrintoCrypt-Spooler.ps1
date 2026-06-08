function Initialize-PrintoCryptSpoolerType {
    if ("PrintoCryptSpooler" -as [type]) {
        return
    }

    Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class PrintoCryptSpooler
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct PrinterDefaults
    {
        public string pDatatype;
        public IntPtr pDevMode;
        public int DesiredAccess;
    }

    [DllImport("winspool.drv", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool OpenPrinter(string pPrinterName, out IntPtr phPrinter, ref PrinterDefaults pDefault);

    [DllImport("winspool.drv", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool ClosePrinter(IntPtr hPrinter);

    [DllImport("winspool.drv", EntryPoint = "XcvDataW", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool XcvData(
        IntPtr hXcv,
        string pszDataName,
        IntPtr pInputData,
        uint cbInputData,
        IntPtr pOutputData,
        uint cbOutputData,
        out uint pcbOutputNeeded,
        out uint pwdStatus);

    private static int RunPortCommand(string portName, string command)
    {
        var defaults = new PrinterDefaults
        {
            pDatatype = null,
            pDevMode = IntPtr.Zero,
            DesiredAccess = 1
        };

        IntPtr hPrinter;
        if (!OpenPrinter(",XcvMonitor Local Port", out hPrinter, ref defaults))
        {
            return Marshal.GetLastWin32Error();
        }

        try
        {
            var bytes = System.Text.Encoding.Unicode.GetBytes(portName + "\0");
            var portPtr = Marshal.AllocHGlobal(bytes.Length);
            try
            {
                Marshal.Copy(bytes, 0, portPtr, bytes.Length);
                uint pcbOutputNeeded;
                uint status;
                if (!XcvData(hPrinter, command, portPtr, (uint)bytes.Length, IntPtr.Zero, 0, out pcbOutputNeeded, out status))
                {
                    return (int)status;
                }

                return 0;
            }
            finally
            {
                Marshal.FreeHGlobal(portPtr);
            }
        }
        finally
        {
            ClosePrinter(hPrinter);
        }
    }

    public static int AddLocalPort(string portName)
    {
        return RunPortCommand(portName, "AddPort");
    }

    public static int DeleteLocalPort(string portName)
    {
        return RunPortCommand(portName, "DeletePort");
    }
}
'@
}

function Get-IncomingPrintFolder {
    return Join-Path $env:ProgramData "PrintoCrypt\incoming"
}

function Get-IncomingPrintPortName {
    $incomingPath = Get-IncomingPrintFolder
    if ($incomingPath.EndsWith('\')) {
        return $incomingPath
    }

    return "$incomingPath\"
}

function Initialize-IncomingPrintFolder {
    param([string]$Path)

    New-Item -ItemType Directory -Force -Path $Path | Out-Null

    $acl = Get-Acl $Path
    foreach ($entry in @(
            @("NT AUTHORITY\SYSTEM", "FullControl"),
            @("BUILTIN\Users", "Modify"))) {
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $entry[0],
            $entry[1],
            "ContainerInherit,ObjectInherit",
            "None",
            "Allow")
        $acl.AddAccessRule($rule)
    }

    Set-Acl -Path $Path -AclObject $acl
}

function Add-LocalPrintPort {
    param([string]$PortName)

    Initialize-PrintoCryptSpoolerType
    return [PrintoCryptSpooler]::AddLocalPort($PortName)
}

function Remove-LocalPrintPort {
    param([string]$PortName)

    Initialize-PrintoCryptSpoolerType
    return [PrintoCryptSpooler]::DeleteLocalPort($PortName)
}
