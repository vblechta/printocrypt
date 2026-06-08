#Requires -RunAsAdministrator
param(
    [string]$PrinterName = "PrintoCrypt",
    [int]$Port = 9150
)

$ErrorActionPreference = "Stop"

Write-Host "Removing PrintoCrypt virtual printer..." -ForegroundColor Cyan

$existingPrinter = Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue
if ($existingPrinter) {
    Remove-Printer -Name $PrinterName
    Write-Host "Removed printer '$PrinterName'"
}
else {
    Write-Host "Printer '$PrinterName' was not found."
}

$portName = "PrintoCrypt_$Port"
$existingPort = Get-PrinterPort -Name $portName -ErrorAction SilentlyContinue
if ($existingPort) {
    Remove-PrinterPort -Name $portName
    Write-Host "Removed port '$portName'"
}

Write-Host "Uninstall complete." -ForegroundColor Green
