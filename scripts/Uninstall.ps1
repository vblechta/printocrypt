#Requires -Version 5.1
param(
    [string]$InstallDir = (Join-Path $env:ProgramFiles "PrintoCrypt"),
    [int]$Port = 9150,
    [string]$PrinterName = "PrintoCrypt",
    [switch]$PrinterOnly,
    [switch]$SkipAppRemoval,
    [switch]$InnoUninstall,
    [switch]$SynchronousCleanup,
    [switch]$DeferredCleanupOnly,
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"

$script:PrintoCryptBrokerServiceName = "PrintoCryptBroker"

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
    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"
    try {
        Write-Step "Removing printer '$PrinterName'..."

        if (Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue) {
            Remove-Printer -Name $PrinterName -ErrorAction SilentlyContinue
            Write-Ok "Removed printer '$PrinterName'"
        }
        elseif (-not $Quiet) {
            Write-Host "Printer '$PrinterName' was not found."
        }

        $portName = "PrintoCrypt_$Port"
        if (Get-PrinterPort -Name $portName -ErrorAction SilentlyContinue) {
            Remove-PrinterPort -Name $portName -ErrorAction SilentlyContinue
            Write-Ok "Removed port '$portName'"
        }

        $pipePortName = '\\.\pipe\PrintoCrypt'
        if (Get-PrinterPort -Name $pipePortName -ErrorAction SilentlyContinue) {
            Remove-PrinterPort -Name $pipePortName -ErrorAction SilentlyContinue
            Write-Ok "Removed legacy port '$pipePortName'"
        }

        $incomingPath = Join-Path $env:ProgramData "PrintoCrypt\incoming"
        $legacyFolderPort = if ($incomingPath.EndsWith('\')) { $incomingPath } else { "$incomingPath\" }
        if (Get-PrinterPort -Name $legacyFolderPort -ErrorAction SilentlyContinue) {
            Remove-PrinterPort -Name $legacyFolderPort -ErrorAction SilentlyContinue
            Write-Ok "Removed legacy port '$legacyFolderPort'"
        }
    }
    finally {
        $ErrorActionPreference = $previousErrorAction
    }
}

function Stop-PrintoCryptProcess {
    Get-Process -Name "PrintoCrypt" -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Step "Stopping PrintoCrypt..."
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    }
}

function Stop-PrintoCryptBrokerService {
    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"
    try {
        Stop-Service -Name $script:PrintoCryptBrokerServiceName -Force -ErrorAction SilentlyContinue | Out-Null
    }
    catch {
    }

    $service = Get-CimInstance Win32_Service -Filter "Name='$($script:PrintoCryptBrokerServiceName)'" -ErrorAction SilentlyContinue
    if (-not $service) {
        $ErrorActionPreference = $previousErrorAction
        return
    }

    try {
        if ($service.State -ne "Stopped") {
            Invoke-CimMethod -InputObject $service -MethodName StopService -ErrorAction SilentlyContinue | Out-Null
            Start-Sleep -Seconds 2
        }
    }
    catch {
    }

    try {
        $service = Get-CimInstance Win32_Service -Filter "Name='$($script:PrintoCryptBrokerServiceName)'" -ErrorAction SilentlyContinue
        if ($service) {
            $deleteResult = Invoke-CimMethod -InputObject $service -MethodName Delete -ErrorAction SilentlyContinue
            if (-not $deleteResult -or $deleteResult.ReturnValue -ne 0) {
                & sc.exe delete $script:PrintoCryptBrokerServiceName 2>$null | Out-Null
            }

            Start-Sleep -Seconds 2
        }
    }
    catch {
        & sc.exe delete $script:PrintoCryptBrokerServiceName 2>$null | Out-Null
    }
    finally {
        $ErrorActionPreference = $previousErrorAction
    }
}

function Wait-PrintoCryptBrokerServiceRemoved {
    param([int]$TimeoutSeconds = 30)

    for ($attempt = 0; $attempt -lt $TimeoutSeconds; $attempt++) {
        $service = Get-CimInstance Win32_Service -Filter "Name='$($script:PrintoCryptBrokerServiceName)'" -ErrorAction SilentlyContinue
        if (-not $service) {
            return $true
        }

        Start-Sleep -Seconds 1
    }

    return $false
}

function Stop-AllPrintoCryptComponents {
    Stop-PrintoCryptProcess
    Stop-PrintoCryptBrokerService
    & sc.exe stop $script:PrintoCryptBrokerServiceName 2>$null | Out-Null
    & sc.exe delete $script:PrintoCryptBrokerServiceName 2>$null | Out-Null
    if (-not (Wait-PrintoCryptBrokerServiceRemoved)) {
        Stop-PrintoCryptProcess
    }
}

function Remove-UninstallRegistryEntries {
    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"
    try {
        foreach ($registryPath in @(
                "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{8F4E2A61-9C3D-4B15-9E7A-1D2F8C6B4A90}_is1",
                "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\PrintoCrypt"
            )) {
            if (Test-Path $registryPath) {
                Remove-Item -Path $registryPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
    finally {
        $ErrorActionPreference = $previousErrorAction
    }
}

function Invoke-SchtasksDelete {
    param([string]$TaskName)

    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"
    try {
        & schtasks.exe /Delete /TN $TaskName /F *> $null
    }
    catch {
    }
    finally {
        $ErrorActionPreference = $previousErrorAction
    }
}

function Remove-StartupRegistration {
    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"
    try {
        $machineRunKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
        if (Test-Path $machineRunKey) {
            Remove-ItemProperty -Path $machineRunKey -Name "PrintoCrypt" -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $machineRunKey -Name "PrintoCrypt Broker" -ErrorAction SilentlyContinue
        }

        Invoke-SchtasksDelete -TaskName "\PrintoCrypt\PrintoCrypt Broker"
        Invoke-SchtasksDelete -TaskName "\PrintoCrypt\PrintoCrypt"
        Unregister-ScheduledTask -TaskName "PrintoCrypt" -TaskPath "\PrintoCrypt\" -Confirm:$false -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName "PrintoCrypt Broker" -TaskPath "\PrintoCrypt\" -Confirm:$false -ErrorAction SilentlyContinue

        Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{8F4E2A61-9C3D-4B15-9E7A-1D2F8C6B4A90}" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "HKLM:\SOFTWARE\PrintoCrypt" -Recurse -Force -ErrorAction SilentlyContinue

        Remove-StartupForInteractiveUser
    }
    finally {
        $ErrorActionPreference = $previousErrorAction
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

function Get-PrintoCryptDeferredCleanupScriptContent {
    param(
        [string]$TargetInstallDir,
        [int]$DelaySeconds = 15
    )

    $escapedDir = $TargetInstallDir.Replace("'", "''")
    $innoUninstallKey = "{8F4E2A61-9C3D-4B15-9E7A-1D2F8C6B4A90}_is1"
    $programsFolder = Join-Path ([Environment]::GetFolderPath("CommonPrograms")) "PrintoCrypt"
    $escapedPrograms = $programsFolder.Replace("'", "''")

    return @"
`$ErrorActionPreference = 'SilentlyContinue'
Start-Sleep -Seconds $DelaySeconds
Stop-Service -Name PrintoCryptBroker -Force -ErrorAction SilentlyContinue
Get-Process -Name PrintoCrypt -ErrorAction SilentlyContinue | Stop-Process -Force
& sc.exe stop PrintoCryptBroker 2>`$null | Out-Null
& sc.exe delete PrintoCryptBroker 2>`$null | Out-Null
Start-Sleep -Seconds 2
if (Test-Path -LiteralPath '$escapedDir') {
    Get-ChildItem -LiteralPath '$escapedDir' -Force -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath '$escapedDir' -Recurse -Force -ErrorAction SilentlyContinue
}
if (Test-Path -LiteralPath '$escapedPrograms') {
    Remove-Item -LiteralPath '$escapedPrograms' -Recurse -Force -ErrorAction SilentlyContinue
}
foreach (`$key in @(
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$innoUninstallKey',
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\PrintoCrypt',
    'HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{8F4E2A61-9C3D-4B15-9E7A-1D2F8C6B4A90}',
    'HKLM:\SOFTWARE\PrintoCrypt'
)) {
    if (Test-Path `$key) {
        Remove-Item -Path `$key -Recurse -Force -ErrorAction SilentlyContinue
    }
}
Remove-Item -LiteralPath `$MyInvocation.MyCommand.Path -Force -ErrorAction SilentlyContinue
"@
}

function Start-DeferredPrintoCryptCleanup {
    param(
        [string]$TargetInstallDir,
        [int]$DelaySeconds = 15
    )

    $cleanupDir = Join-Path $env:ProgramData "PrintoCrypt"
    New-Item -ItemType Directory -Path $cleanupDir -Force | Out-Null
    $cleanupScript = Join-Path $cleanupDir "deferred-uninstall.ps1"
    Get-PrintoCryptDeferredCleanupScriptContent -TargetInstallDir $TargetInstallDir -DelaySeconds $DelaySeconds |
        Set-Content -Path $cleanupScript -Encoding UTF8 -Force

    Start-Process -FilePath "powershell.exe" -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-WindowStyle", "Hidden",
        "-File", $cleanupScript
    ) -WindowStyle Hidden | Out-Null
}

function Invoke-DeferredPrintoCryptCleanup {
    param(
        [string]$TargetInstallDir,
        [int]$DelaySeconds = 3
    )

    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"
    try {
        Start-Sleep -Seconds $DelaySeconds
        Stop-Service -Name $script:PrintoCryptBrokerServiceName -Force -ErrorAction SilentlyContinue
        Get-Process -Name "PrintoCrypt" -ErrorAction SilentlyContinue | Stop-Process -Force
        & sc.exe stop $script:PrintoCryptBrokerServiceName 2>$null | Out-Null
        & sc.exe delete $script:PrintoCryptBrokerServiceName 2>$null | Out-Null
        Start-Sleep -Seconds 2

        if (Test-Path -LiteralPath $TargetInstallDir) {
            $installDirLiteral = (Resolve-Path -LiteralPath $TargetInstallDir).Path
            Get-ChildItem -LiteralPath $installDirLiteral -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -ne $PSCommandPath } |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $installDirLiteral -Recurse -Force -ErrorAction SilentlyContinue
        }

        $programsFolder = Join-Path ([Environment]::GetFolderPath("CommonPrograms")) "PrintoCrypt"
        if (Test-Path $programsFolder) {
            Remove-Item -Path $programsFolder -Recurse -Force -ErrorAction SilentlyContinue
        }

        Remove-UninstallRegistryEntries

        if (Test-Path -LiteralPath $TargetInstallDir) {
            Start-DeferredPrintoCryptCleanup -TargetInstallDir $TargetInstallDir -DelaySeconds 5
        }
    }
    finally {
        $ErrorActionPreference = $previousErrorAction
    }
}

function Remove-PrintoCryptApp {
    param([switch]$SkipDirectoryRemoval)

    Write-Step "Removing PrintoCrypt from '$InstallDir'..."

    Remove-StartupRegistration
    Remove-Shortcuts

    if ($SkipDirectoryRemoval -or -not (Test-Path $InstallDir)) {
        return
    }

    $installDirLiteral = (Resolve-Path $InstallDir).Path
    $runningFromInstallDir = $PSCommandPath.StartsWith($installDirLiteral, [StringComparison]::OrdinalIgnoreCase)

    if ($runningFromInstallDir) {
        Get-ChildItem -LiteralPath $installDirLiteral -Force |
            Where-Object { $_.FullName -ne $PSCommandPath } |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

        $cleanupCommand = "Start-Sleep -Seconds 5; Remove-Item -LiteralPath '$installDirLiteral' -Recurse -Force -ErrorAction SilentlyContinue"
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

try {
    if ($DeferredCleanupOnly) {
        Invoke-DeferredPrintoCryptCleanup -TargetInstallDir $InstallDir
        exit 0
    }

    if (-not $PrinterOnly) {
        Write-Step "Uninstalling PrintoCrypt..."
    }

    Stop-AllPrintoCryptComponents

    $exePath = Join-Path $InstallDir "PrintoCrypt.exe"
    $installedVersion = Get-InstalledPrintoCryptVersionForUninstall -InstallDir $InstallDir -ExePath $exePath

    if (-not $PrinterOnly) {
        if (Get-Command Send-PrintoCryptAnalytics -ErrorAction SilentlyContinue) {
            Send-PrintoCryptAnalytics -Action uninstall -Version $installedVersion
        }
    }

    Remove-PrintoCryptPrinter

    if (-not $PrinterOnly) {
        Remove-PrintoCryptApp -SkipDirectoryRemoval:$true
        Remove-UninstallRegistryEntries

        if ($SynchronousCleanup) {
            Invoke-DeferredPrintoCryptCleanup -TargetInstallDir $InstallDir -DelaySeconds 3
        }
        elseif ($InnoUninstall -or $SkipAppRemoval) {
            Start-DeferredPrintoCryptCleanup -TargetInstallDir $InstallDir
        }
        else {
            Invoke-DeferredPrintoCryptCleanup -TargetInstallDir $InstallDir -DelaySeconds 1
        }

        Write-Ok "PrintoCrypt uninstalled."
    }
    else {
        Write-Ok "Printer removed."
    }
}
catch {
    $message = $_.Exception.Message
    try {
        $logDir = Join-Path $env:ProgramData "PrintoCrypt"
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        $logLine = "{0:yyyy-MM-dd HH:mm:ss} Uninstall failed: {1}`n{2}" -f (Get-Date), $message, $_.ScriptStackTrace
        Add-Content -Path (Join-Path $logDir "uninstall.log") -Value $logLine -Encoding UTF8
    }
    catch {
    }

    Show-UninstallFailure -Message $message
    exit 1
}
