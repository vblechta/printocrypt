#Requires -Version 5.1
param(
    [string]$InstallDir = (Join-Path $env:ProgramFiles "PrintoCrypt"),
    [int]$Port = 9150,
    [string]$PrinterName = "PrintoCrypt",
    [switch]$PrinterOnly,
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"

$SpoolerScript = Join-Path $PSScriptRoot "PrintoCrypt-Spooler.ps1"
if (Test-Path $SpoolerScript) {
    . $SpoolerScript
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

function Remove-PrintoCryptApp {
    Write-Step "Removing PrintoCrypt from '$InstallDir'..."

    Get-Process -Name "PrintoCrypt" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

    Remove-StartupForInteractiveUser
    Remove-Shortcuts

    $uninstallKey = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\PrintoCrypt"
    if (Test-Path $uninstallKey) {
        Remove-Item -Path $uninstallKey -Recurse -Force
    }

    if (Test-Path $InstallDir) {
        Remove-Item -Path $InstallDir -Recurse -Force
    }
}

try {
    if (-not $PrinterOnly) {
        Write-Step "Uninstalling PrintoCrypt..."
    }

    Remove-PrintoCryptPrinter

    if (-not $PrinterOnly) {
        Remove-PrintoCryptApp
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
