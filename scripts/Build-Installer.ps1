#Requires -Version 5.1
param(
    [string]$OutputDir = (Join-Path $PSScriptRoot "..\artifacts\PrintoCrypt-Setup"),
    [string]$Configuration = "Release",
    [string]$Runtime = "win-x64"
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$solutionPath = Join-Path $repoRoot "PrintoCrypt.sln"
$projectPath = Join-Path $repoRoot "src\PrintoCrypt.App\PrintoCrypt.App.csproj"
$appOutputDir = Join-Path $OutputDir "app"

Write-Host "Building PrintoCrypt..." -ForegroundColor Cyan

if (Test-Path $OutputDir) {
    Remove-Item -Path $OutputDir -Recurse -Force
}

New-Item -ItemType Directory -Path $appOutputDir -Force | Out-Null

Push-Location $repoRoot
try {
    dotnet restore $solutionPath
    if ($LASTEXITCODE -ne 0) { throw "dotnet restore failed." }

    dotnet publish $projectPath -c $Configuration -r $Runtime --self-contained false -o $appOutputDir
    if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed." }
}
finally {
    Pop-Location
}

Write-Host "Preparing setup package at '$OutputDir'..." -ForegroundColor Cyan

Copy-Item -Path (Join-Path $PSScriptRoot "Install.ps1") -Destination (Join-Path $OutputDir "Install.ps1") -Force
Copy-Item -Path (Join-Path $PSScriptRoot "Uninstall.ps1") -Destination (Join-Path $OutputDir "Uninstall.ps1") -Force
Copy-Item -Path (Join-Path $PSScriptRoot "PrintoCrypt-Spooler.ps1") -Destination (Join-Path $OutputDir "PrintoCrypt-Spooler.ps1") -Force
Copy-Item -Path (Join-Path $repoRoot "Install.cmd") -Destination (Join-Path $OutputDir "Install.cmd") -Force
Copy-Item -Path (Join-Path $repoRoot "Uninstall.cmd") -Destination (Join-Path $OutputDir "Uninstall.cmd") -Force

$zipPath = Join-Path (Split-Path $OutputDir -Parent) "PrintoCrypt-Setup.zip"
if (Test-Path $zipPath) {
    Remove-Item -Path $zipPath -Force
}

Compress-Archive -Path (Join-Path $OutputDir "*") -DestinationPath $zipPath

Write-Host ""
Write-Host "Validating printer installation prerequisites..." -ForegroundColor Cyan
$validationScript = Join-Path $PSScriptRoot "Test-InstallPrinterPort.ps1"
& $validationScript
if ($LASTEXITCODE -eq 1) {
    throw "Printer port validation failed. Fix Install.ps1 before shipping the setup package."
}
if ($LASTEXITCODE -eq 2) {
    Write-Host "Skipped printer port validation because the build is not running as administrator." -ForegroundColor Yellow
    Write-Host "Run this before release: powershell -ExecutionPolicy Bypass -File scripts\Test-InstallPrinterPort.ps1" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Setup package created:" -ForegroundColor Green
Write-Host "  Folder: $OutputDir"
Write-Host "  Zip:    $zipPath"
Write-Host ""
Write-Host "Run Install.cmd as administrator to install everything." -ForegroundColor Yellow
