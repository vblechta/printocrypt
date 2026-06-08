#Requires -Version 5.1
param(
    [int]$Port = 9150,
    [string]$HostAddress = "127.0.0.1"
)

$ErrorActionPreference = 'Stop'

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    Write-Host "Printer port validation requires administrator rights. Skipping." -ForegroundColor Yellow
    exit 2
}

$portName = "PrintoCrypt_$Port"
$testPrinter = 'PrintoCryptInstallValidation'

if (-not (Get-PrinterPort -Name $portName -ErrorAction SilentlyContinue)) {
    Add-PrinterPort -Name $portName -PrinterHostAddress $HostAddress -PortNumber $Port
}

if (-not (Get-PrinterPort -Name $portName -ErrorAction SilentlyContinue)) {
    Write-Error "TCP printer port '$portName' was not created."
}

$driverName = (Get-PrinterDriver -Name 'Microsoft Print To PDF' -ErrorAction SilentlyContinue).Name
if (-not $driverName) {
    $driverName = (Get-PrinterDriver | Where-Object { $_.Name -match 'Print To PDF|OpenXPS|XPS Class' } | Select-Object -First 1).Name
}

if (-not $driverName) {
    Write-Error "No suitable printer driver was found for validation."
}

if (Get-Printer -Name $testPrinter -ErrorAction SilentlyContinue) {
    Remove-Printer -Name $testPrinter
}

try {
    Add-Printer -Name $testPrinter -DriverName $driverName -PortName $portName
}
catch {
    Write-Error "Add-Printer validation failed: $($_.Exception.Message)"
}
finally {
    if (Get-Printer -Name $testPrinter -ErrorAction SilentlyContinue) {
        Remove-Printer -Name $testPrinter
    }
}

Write-Host "Printer port validation passed for '$portName' using driver '$driverName'." -ForegroundColor Green
