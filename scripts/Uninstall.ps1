#Requires -Version 5.1
param(
    [string]$InstallDir = (Join-Path $env:ProgramFiles "PrintoCrypt"),
    [int]$Port = 9150,
    [string]$PrinterName = "PrintoCrypt",
    [switch]$PrinterOnly,
    [switch]$SkipAppRemoval,
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"

$SpoolerScript = Join-Path $PSScriptRoot "PrintoCrypt-Spooler.ps1"
if (Test-Path $SpoolerScript) {
    . $SpoolerScript
}

$AnalyticsScript = Join-Path $PSScriptRoot "PrintoCrypt-Analytics.ps1"
if (-not (Test-Path $AnalyticsScript)) {
    $AnalyticsScript = Join-Path $InstallDir "PrintoCrypt-Analytics.ps1"
}
if (Test-Path $AnalyticsScript) {
    . $AnalyticsScript
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Request-Elevation {
    $argumentList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $PSCommandPath)

    foreach ($key in $PSBoundParameters.Keys) {
        $value = $PSBoundParameters[$key]
        if ($value -is [switch]) {
            if ($value) {
                $argumentList += "-$key"
            }
        }
        elseif ($null -ne $value -and "$value".Length -gt 0) {
            $argumentList += "-$key"
            $argumentList += "$value"
        }
    }

    $process = Start-Process -FilePath "powershell.exe" -Verb RunAs -Wait -PassThru -ArgumentList $argumentList
    exit $process.ExitCode
}

if (-not (Test-IsAdministrator)) {
    Request-Elevation
}

function Write-Step([string]$Message) {
    if (-not $Quiet) {
        Write-Host $Message -ForegroundColor Cyan
    }
}

function Write-Ok([string]$Message) {
    if (-not $Quiet) {
        Write-Host $Message -ForegroundColor Green
    }
}

function Show-UninstallFailure {
    param([string]$Message)

    if (-not $Quiet) {
        Write-Host "Uninstall failed: $Message" -ForegroundColor Red
        if ([Environment]::UserInteractive) {
            Read-Host "Press Enter to close"
        }
    }
}

function Get-InteractiveUser {
    $session = Get-CimInstance -ClassName Win32_ComputerSystem
    if ($session.UserName) {
        return $session.UserName
    }

    return $null
}

function Remove-PrintoCryptPrinter {
    Write-Step "Removing printer '$PrinterName'..."

    if (Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue) {
        Remove-Printer -Name $PrinterName
        Write-Ok "Removed printer '$PrinterName'"
    }
    elseif (-not $Quiet) {
        Write-Host "Printer '$PrinterName' was not found."
    }

    $portName = "PrintoCrypt_$Port"
    if (Get-PrinterPort -Name $portName -ErrorAction SilentlyContinue) {
        Remove-PrinterPort -Name $portName
        Write-Ok "Removed port '$portName'"
    }

    $pipePortName = '\\.\pipe\PrintoCrypt'
    if (Get-PrinterPort -Name $pipePortName -ErrorAction SilentlyContinue) {
        Remove-PrinterPort -Name $pipePortName
        Write-Ok "Removed legacy port '$pipePortName'"
    }

    $incomingPath = Join-Path $env:ProgramData "PrintoCrypt\incoming"
    $legacyFolderPort = if ($incomingPath.EndsWith('\')) { $incomingPath } else { "$incomingPath\" }
    if (Get-PrinterPort -Name $legacyFolderPort -ErrorAction SilentlyContinue) {
        Remove-PrinterPort -Name $legacyFolderPort -ErrorAction SilentlyContinue
        Write-Ok "Removed legacy port '$legacyFolderPort'"
    }
}

function Remove-StartupForInteractiveUser {
    $userName = Get-InteractiveUser
    if (-not $userName) {
        return
    }

    $account = New-Object System.Security.Principal.NTAccount($userName)
    $sid = $account.Translate([System.Security.Principal.SecurityIdentifier]).Value
    $runKeyPath = "Registry::HKEY_USERS\$sid\Software\Microsoft\Windows\CurrentVersion\Run"

    if (Test-Path $runKeyPath) {
        Remove-ItemProperty -Path $runKeyPath -Name "PrintoCrypt" -ErrorAction SilentlyContinue
    }
}

function Remove-Shortcuts {
    $programFolder = Join-Path ([Environment]::GetFolderPath("CommonPrograms")) "PrintoCrypt"
    if (Test-Path $programFolder) {
        Remove-Item -Path $programFolder -Recurse -Force
    }
}

function Get-InstalledPrintoCryptVersionForUninstall {
    param(
        [string]$InstallDir,
        [string]$ExePath
    )

    foreach ($registryPath in @(
            "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{8F4E2A61-9C3D-4B15-9E7A-1D2F8C6B4A90}_is1",
            "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\PrintoCrypt"
        )) {
        if (-not (Test-Path $registryPath)) {
            continue
        }

        $registryVersion = (Get-ItemProperty -Path $registryPath -Name DisplayVersion -ErrorAction SilentlyContinue).DisplayVersion
        if (-not [string]::IsNullOrWhiteSpace($registryVersion)) {
            return [string]$registryVersion
        }
    }

    if (Get-Command Get-PrintoCryptVersionFromExe -ErrorAction SilentlyContinue) {
        return Get-PrintoCryptVersionFromExe -ExePath $ExePath
    }

    if (-not (Test-Path $ExePath)) {
        return "unknown"
    }

    $fileVersion = (Get-Item $ExePath).VersionInfo
    $version = $fileVersion.ProductVersion
    if ([string]::IsNullOrWhiteSpace($version)) {
        $version = $fileVersion.FileVersion
    }

    if ([string]::IsNullOrWhiteSpace($version)) {
        return "unknown"
    }

    return $version
}

function Remove-PrintoCryptApp {
    param([switch]$SkipDirectoryRemoval)

    Write-Step "Removing PrintoCrypt from '$InstallDir'..."

    Get-Process -Name "PrintoCrypt" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

    Remove-StartupForInteractiveUser
    Remove-Shortcuts

    $uninstallKey = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\PrintoCrypt"
    if (Test-Path $uninstallKey) {
        Remove-Item -Path $uninstallKey -Recurse -Force
    }

    if ($SkipDirectoryRemoval -or -not (Test-Path $InstallDir)) {
        return
    }

    $installDirLiteral = (Resolve-Path $InstallDir).Path
    $runningFromInstallDir = $PSCommandPath.StartsWith($installDirLiteral, [StringComparison]::OrdinalIgnoreCase)

    if ($runningFromInstallDir) {
        Get-ChildItem -LiteralPath $installDirLiteral -Force |
            Where-Object { $_.FullName -ne $PSCommandPath } |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

        $cleanupCommand = "Start-Sleep -Seconds 3; Remove-Item -LiteralPath '$installDirLiteral' -Recurse -Force -ErrorAction SilentlyContinue"
        Start-Process -FilePath "powershell.exe" -ArgumentList @(
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-WindowStyle", "Hidden",
            "-Command", $cleanupCommand
        ) -WindowStyle Hidden | Out-Null
        return
    }

    Remove-Item -LiteralPath $installDirLiteral -Recurse -Force
}

try {
    if (-not $PrinterOnly) {
        Write-Step "Uninstalling PrintoCrypt..."
    }

    $exePath = Join-Path $InstallDir "PrintoCrypt.exe"
    $installedVersion = Get-InstalledPrintoCryptVersionForUninstall -InstallDir $InstallDir -ExePath $exePath

    if (-not $PrinterOnly) {
        if (Get-Command Send-PrintoCryptAnalytics -ErrorAction SilentlyContinue) {
            Send-PrintoCryptAnalytics -Action uninstall -Version $installedVersion
        }
    }

    Remove-PrintoCryptPrinter

    if (-not $PrinterOnly) {
        Remove-PrintoCryptApp -SkipDirectoryRemoval:$SkipAppRemoval
        Write-Ok "PrintoCrypt uninstalled."
    }
    else {
        Write-Ok "Printer removed."
    }
}
catch {
    Show-UninstallFailure -Message $_.Exception.Message
    exit 1
}
