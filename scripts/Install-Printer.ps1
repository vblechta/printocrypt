#Requires -RunAsAdministrator
param(
    [string]$PrinterName = "PrintoCrypt",
    [int]$Port = 9150,
    [string]$HostAddress = "127.0.0.1"
)

$ErrorActionPreference = "Stop"

function Get-PostScriptDriverName {
    $preferred = @(
        "Microsoft PS Class Driver",
        "Microsoft PS Class Driver v4",
        "MS Publisher Imagesetter"
    )

    foreach ($name in $preferred) {
        if (Get-PrinterDriver -Name $name -ErrorAction SilentlyContinue) {
            return $name
        }
    }

    $fallback = Get-PrinterDriver |
        Where-Object { $_.Name -match "PS Class|PostScript|Imagesetter" } |
        Select-Object -First 1

    if ($fallback) {
        return $fallback.Name
    }

    throw "No PostScript printer driver found. Install 'Microsoft PS Class Driver' from Windows Optional Features or add a PostScript-capable driver."
}

Write-Host "Installing PrintoCrypt virtual printer..." -ForegroundColor Cyan

$portName = "PrintoCrypt_$Port"
$existingPort = Get-PrinterPort -Name $portName -ErrorAction SilentlyContinue
if (-not $existingPort) {
    Add-PrinterPort -Name $portName -PrinterHostAddress $HostAddress -PortNumber $Port
    Write-Host "Created TCP/IP port $HostAddress`:$Port"
}

$driverName = Get-PostScriptDriverName
Write-Host "Using driver: $driverName"

$existingPrinter = Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue
if ($existingPrinter) {
    Remove-Printer -Name $PrinterName
    Write-Host "Removed existing printer '$PrinterName'"
}

Add-Printer -Name $PrinterName -DriverName $driverName -PortName $portName
Write-Host ""
Write-Host "Printer '$PrinterName' installed successfully." -ForegroundColor Green
Write-Host "Make sure PrintoCrypt is running in the system tray before printing."
Write-Host "Default listen address: $HostAddress`:$Port"
