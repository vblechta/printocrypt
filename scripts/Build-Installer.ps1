#Requires -Version 5.1
param(
    [string]$OutputDir = (Join-Path $PSScriptRoot "..\artifacts\PrintoCrypt-Setup"),
    [string]$Configuration = "Release",
    [string]$Runtime = "win-x64",
    [switch]$SkipInno
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$solutionPath = Join-Path $repoRoot "PrintoCrypt.sln"
$projectPath = Join-Path $repoRoot "src\PrintoCrypt.App\PrintoCrypt.App.csproj"
$appOutputDir = Join-Path $OutputDir "app"
$issPath = Join-Path $repoRoot "installer\PrintoCrypt.iss"

function Get-AppVersion {
    $propsPath = Join-Path $repoRoot "Directory.Build.props"
    if (Test-Path $propsPath) {
        [xml]$props = Get-Content $propsPath
        $version = [string]$props.Project.PropertyGroup.Version
        if ($version) {
            return $version
        }
    }

    [xml]$project = Get-Content $projectPath
    return [string]$project.Project.PropertyGroup.Version
}

Write-Host "Building PrintoCrypt..." -ForegroundColor Cyan

if (Test-Path $OutputDir) {
    Remove-Item -Path $OutputDir -Recurse -Force
}

New-Item -ItemType Directory -Path $appOutputDir -Force | Out-Null

Push-Location $repoRoot
try {
    dotnet restore $solutionPath
    if ($LASTEXITCODE -ne 0) { throw "dotnet restore failed." }

    dotnet publish $projectPath -c $Configuration -r $Runtime --self-contained true -p:PublishSingleFile=false -o $appOutputDir
    if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed." }
}
finally {
    Pop-Location
}

Write-Host "Preparing setup package at '$OutputDir'..." -ForegroundColor Cyan

Copy-Item -Path (Join-Path $PSScriptRoot "Install.ps1") -Destination (Join-Path $OutputDir "Install.ps1") -Force
Copy-Item -Path (Join-Path $PSScriptRoot "Uninstall.ps1") -Destination (Join-Path $OutputDir "Uninstall.ps1") -Force
Copy-Item -Path (Join-Path $PSScriptRoot "PrintoCrypt-Spooler.ps1") -Destination (Join-Path $OutputDir "PrintoCrypt-Spooler.ps1") -Force
Copy-Item -Path (Join-Path $PSScriptRoot "PrintoCrypt-Analytics.ps1") -Destination (Join-Path $OutputDir "PrintoCrypt-Analytics.ps1") -Force
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

function Find-InnoSetupCompiler {
    $candidates = @(
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
        "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
        (Join-Path $env:LOCALAPPDATA "Programs\Inno Setup 6\ISCC.exe")
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    $uninstallRoots = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    foreach ($root in $uninstallRoots) {
        $installLocation = Get-ItemProperty $root -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like "Inno Setup*" -and $_.InstallLocation } |
            Select-Object -ExpandProperty InstallLocation -First 1

        if ($installLocation) {
            foreach ($relativePath in @("ISCC.exe", "bin\ISCC.exe")) {
                $candidate = Join-Path $installLocation $relativePath
                if (Test-Path $candidate) {
                    return $candidate
                }
            }
        }
    }

    return $null
}

$appVersion = Get-AppVersion
$guiInstallerPath = Join-Path (Split-Path $OutputDir -Parent) "PrintoCrypt-Setup.exe"

if (-not $SkipInno) {
    $iscc = Find-InnoSetupCompiler

    if ($iscc) {
        Write-Host ""
        Write-Host "Building GUI installer..." -ForegroundColor Cyan
        & $iscc "/DMyAppVersion=$appVersion" $issPath
        if ($LASTEXITCODE -ne 0) {
            throw "Inno Setup compilation failed."
        }
    }
    else {
        Write-Host ""
        Write-Host "Inno Setup 6 was not found. Install it to build PrintoCrypt-Setup.exe:" -ForegroundColor Yellow
        Write-Host "  winget install --id JRSoftware.InnoSetup --source winget" -ForegroundColor Yellow
        Write-Host "  https://jrsoftware.org/isdl.php" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "Setup package created:" -ForegroundColor Green
Write-Host "  Folder: $OutputDir"
Write-Host "  Zip:    $zipPath"
if (Test-Path $guiInstallerPath) {
    Write-Host "  GUI:    $guiInstallerPath"
    Write-Host ""
    Write-Host "Quiet install examples:" -ForegroundColor Yellow
    Write-Host "  PrintoCrypt-Setup.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART"
    Write-Host "  PrintoCrypt-Setup.exe /SILENT"
}
else {
    Write-Host ""
    Write-Host "Run Install.cmd as administrator to install from the zip/folder package." -ForegroundColor Yellow
}
