#Requires -Version 5.1
param(
    [string]$InstallDir = (Split-Path $PSCommandPath -Parent)
)

$ErrorActionPreference = "SilentlyContinue"

$exePath = Join-Path $InstallDir "PrintoCrypt.exe"
if (-not (Test-Path $exePath)) {
    exit 0
}

$machineSettingsPath = Join-Path $env:ProgramData "PrintoCrypt\machine-settings.json"
$port = 9150
$printerName = "PrintoCrypt"

if (Test-Path $machineSettingsPath) {
    try {
        $machineSettings = Get-Content -Path $machineSettingsPath -Raw | ConvertFrom-Json
        if ($null -ne $machineSettings.listenPort) {
            $port = [int]$machineSettings.listenPort
        }

        if ($machineSettings.printerName) {
            $printerName = [string]$machineSettings.printerName
        }
    }
    catch {
    }
}

$settingsDir = Join-Path $env:APPDATA "PrintoCrypt"
$settingsPath = Join-Path $settingsDir "settings.json"
New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null

if (-not (Test-Path $settingsPath)) {
    $outputDirectory = Join-Path ([Environment]::GetFolderPath("MyDocuments")) "PrintoCrypt"
    $settings = [ordered]@{
        listenPort                = $port
        printerName               = $printerName
        outputDirectory           = $outputDirectory
        openOutputFolderAfterSave = $false
        openOutlookAfterSave      = $true
        startWithWindows          = $true
    }

    ($settings | ConvertTo-Json -Depth 4) | Set-Content -Path $settingsPath -Encoding UTF8
}

$userLauncher = Join-Path $InstallDir "PrintoCrypt-UserLaunch.cmd"
if (-not (Test-Path $userLauncher)) {
    $configKey = "HKLM:\SOFTWARE\PrintoCrypt"
    if (Test-Path $configKey) {
        $configuredLauncher = (Get-ItemProperty -Path $configKey -Name "UserLauncher" -ErrorAction SilentlyContinue).UserLauncher
        if ($configuredLauncher -and (Test-Path $configuredLauncher)) {
            $userLauncher = [string]$configuredLauncher
        }
    }
}

if (Test-Path $userLauncher) {
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "PrintoCrypt" -Value "`"$userLauncher`"" -Type String
}

$currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
foreach ($process in Get-CimInstance Win32_Process -Filter "Name='PrintoCrypt.exe'") {
    $owner = Invoke-CimMethod -InputObject $process -MethodName GetOwner
    if ($owner.ReturnValue -ne 0 -or [string]::IsNullOrWhiteSpace($owner.User)) {
        continue
    }

    $processIdentity = if ($owner.Domain -and $owner.Domain -notin @(".", $env:COMPUTERNAME)) {
        "$($owner.Domain)\$($owner.User)"
    }
    else {
        "$env:USERDOMAIN\$($owner.User)"
    }

    if ($processIdentity.Equals($currentIdentity, [StringComparison]::OrdinalIgnoreCase)) {
        if ($process.CommandLine -notlike "*--broker*") {
            exit 0
        }
    }
}

if (Test-Path $userLauncher) {
    Start-Process -FilePath $userLauncher -WorkingDirectory $InstallDir -WindowStyle Hidden
}
else {
    Start-Process -LiteralPath $exePath -WorkingDirectory $InstallDir -WindowStyle Hidden
}

exit 0
