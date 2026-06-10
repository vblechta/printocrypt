#Requires -Version 5.1
param(
    [string]$InstallDir = (Join-Path $env:ProgramFiles "PrintoCrypt"),
    [int]$Port = 9150,
    [string]$PrinterName = "PrintoCrypt",
    [string]$HostAddress = "127.0.0.1",
    [switch]$PrinterOnly,
    [switch]$SkipLaunch,
    [switch]$SkipAppCopy,
    [switch]$Quiet,
    [string]$ResultFile = "",
    [ValidateSet("install", "update", "")]
    [string]$AnalyticsAction = ""
)

$ErrorActionPreference = "Stop"

$SpoolerScript = Join-Path $PSScriptRoot "PrintoCrypt-Spooler.ps1"
if (Test-Path $SpoolerScript) {
    . $SpoolerScript
}

$AnalyticsScript = Join-Path $PSScriptRoot "PrintoCrypt-Analytics.ps1"
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

function Write-Result {
    param(
        [bool]$Success,
        [string]$Message
    )

    if ([string]::IsNullOrWhiteSpace($ResultFile)) {
        return
    }

    [ordered]@{
        success = $Success
        message = $Message
    } | ConvertTo-Json -Compress | Set-Content -Path $ResultFile -Encoding UTF8
}

function Show-InstallFailure {
    param([string]$Message)

    if (-not $Quiet) {
        Write-Host ""
        Write-Host "Installation failed: $Message" -ForegroundColor Red

        if ([string]::IsNullOrWhiteSpace($ResultFile) -and [Environment]::UserInteractive) {
            Read-Host "Press Enter to close"
        }
    }
}

function Get-VersionPart {
    param([ref]$VersionText)

    if ([string]::IsNullOrWhiteSpace($VersionText.Value)) {
        return 0
    }

    $dotIndex = $VersionText.Value.IndexOf(".")
    if ($dotIndex -ge 0) {
        $partText = $VersionText.Value.Substring(0, $dotIndex)
        $VersionText.Value = $VersionText.Value.Substring($dotIndex + 1)
    }
    else {
        $partText = $VersionText.Value
        $VersionText.Value = ""
    }

    if ([string]::IsNullOrWhiteSpace($partText)) {
        return 0
    }

    return [int]$partText
}

function Compare-VersionStrings {
    param(
        [string]$Left,
        [string]$Right
    )

    $leftText = $Left
    $rightText = $Right

    for ($index = 0; $index -lt 4; $index++) {
        $leftPart = Get-VersionPart ([ref]$leftText)
        $rightPart = Get-VersionPart ([ref]$rightText)

        if ($leftPart -gt $rightPart) {
            return 1
        }

        if ($leftPart -lt $rightPart) {
            return -1
        }
    }

    return 0
}

function Get-InstalledPrintoCryptVersion {
    param([string]$InstallDir)

    $candidates = @()

    foreach ($registryPath in @(
            "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{8F4E2A61-9C3D-4B15-9E7A-1D2F8C6B4A90}_is1",
            "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\PrintoCrypt"
        )) {
        if (-not (Test-Path $registryPath)) {
            continue
        }

        $registryVersion = (Get-ItemProperty -Path $registryPath -Name DisplayVersion -ErrorAction SilentlyContinue).DisplayVersion
        if (-not [string]::IsNullOrWhiteSpace($registryVersion)) {
            $candidates += [string]$registryVersion
        }
    }

    $exePath = Join-Path $InstallDir "PrintoCrypt.exe"
    if (Test-Path $exePath) {
        $exeVersion = Get-PrintoCryptVersionFromExe -ExePath $exePath
        if ($exeVersion -ne "unknown") {
            $candidates += $exeVersion
        }
    }

    if ($candidates.Count -eq 0) {
        return $null
    }

    $bestVersion = $candidates[0]
    foreach ($candidate in $candidates[1..($candidates.Count - 1)]) {
        if ((Compare-VersionStrings -Left $candidate -Right $bestVersion) -gt 0) {
            $bestVersion = $candidate
        }
    }

    return $bestVersion
}

function Resolve-InstallAnalyticsAction {
    param(
        [string]$InstallDir,
        [string]$InstallerVersion
    )

    $installedVersion = Get-InstalledPrintoCryptVersion -InstallDir $InstallDir
    if ($null -eq $installedVersion) {
        return @{
            ShouldSkip = $false
            Action     = "install"
        }
    }

    if ((Compare-VersionStrings -Left $installedVersion -Right $InstallerVersion) -ge 0) {
        return @{
            ShouldSkip = $true
            Action     = ""
        }
    }

    return @{
        ShouldSkip = $false
        Action     = "update"
    }
}

function Get-InteractiveUser {
    $session = Get-CimInstance -ClassName Win32_ComputerSystem
    if ($session.UserName) {
        return $session.UserName
    }

    return $null
}

function Get-InteractiveUserSid {
    $userName = Get-InteractiveUser
    if (-not $userName) {
        return $null
    }

    $account = New-Object System.Security.Principal.NTAccount($userName)
    return $account.Translate([System.Security.Principal.SecurityIdentifier]).Value
}

function Get-InteractiveUserShellFolder {
    param([string]$FolderValueName)

    $sid = Get-InteractiveUserSid
    if (-not $sid) {
        return $null
    }

    $profileKey = "Registry::HKEY_USERS\$sid\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders"

    try {
        $path = (Get-Item $profileKey).GetValue($FolderValueName)
        if ($path) {
            return [Environment]::ExpandEnvironmentVariables([string]$path)
        }
    }
    catch {
    }

    return $null
}

function Get-InteractiveUserAppData {
    $appData = Get-InteractiveUserShellFolder -FolderValueName "AppData"
    if ($appData) {
        return $appData
    }

    return $env:APPDATA
}

function Resolve-PackageRoot {
    $startDirs = New-Object System.Collections.Generic.List[string]
    $scriptDir = Split-Path $PSCommandPath -Parent
    $startDirs.Add($scriptDir) | Out-Null

    if ((Split-Path $scriptDir -Leaf) -eq "scripts") {
        $repoRoot = Split-Path $scriptDir -Parent
        $startDirs.Add($repoRoot) | Out-Null
        $startDirs.Add((Join-Path $repoRoot "artifacts\PrintoCrypt-Setup")) | Out-Null
        $startDirs.Add((Join-Path $repoRoot "publish")) | Out-Null
    }

    foreach ($startDir in $startDirs) {
        if (-not (Test-Path $startDir)) {
            continue
        }

        $dir = (Resolve-Path $startDir).Path
        for ($i = 0; $i -lt 3; $i++) {
            if (Test-Path (Join-Path $dir "app\PrintoCrypt.exe")) {
                return $dir
            }

            if (Test-Path (Join-Path $dir "PrintoCrypt.exe")) {
                return $dir
            }

            $parent = Split-Path $dir -Parent
            if ($parent -eq $dir) {
                break
            }

            $dir = $parent
        }
    }

    throw "Could not find PrintoCrypt.exe. Run Build-Installer.ps1 first, or run Install.ps1 from the setup package folder."
}

function Resolve-SourceAppDir {
    param([string]$Root)

    foreach ($candidate in @(
        (Join-Path $Root "app"),
        (Join-Path $Root "publish"),
        $Root
    )) {
        if (Test-Path (Join-Path $candidate "PrintoCrypt.exe")) {
            return (Resolve-Path $candidate).Path
        }
    }

    throw "Could not find PrintoCrypt.exe under '$Root'."
}

function Stop-PrintoCryptProcess {
    Get-Process -Name "PrintoCrypt" -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Step "Stopping PrintoCrypt..."
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    }
}

function Get-PrintDriverInfPath {
    foreach ($pattern in @("prnms005.inf", "prnms007.inf", "prnms003.inf")) {
        $inf = Get-ChildItem -Path "$env:windir\System32\DriverStore\FileRepository" -Recurse -Filter $pattern -ErrorAction SilentlyContinue |
            Select-Object -First 1

        if ($inf) {
            return $inf.FullName
        }
    }

    return $null
}

function Install-PrintDriverFromInf {
    param(
        [string]$DriverName,
        [string]$InfPath
    )

    Write-Step "Installing printer driver '$DriverName'..."

    try {
        Add-PrinterDriver -Name $DriverName -InfPath $InfPath -ErrorAction Stop
        return
    }
    catch {
        Write-Host "Add-PrinterDriver failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    & pnputil.exe /add-driver $InfPath /install | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "Could not install '$DriverName' from '$InfPath' (pnputil exit code $LASTEXITCODE)."
    }

    Add-PrinterDriver -Name $DriverName -InfPath $InfPath -ErrorAction Stop
}

function Get-PrintDriverName {
    $preferred = @(
        "Microsoft Print To PDF",
        "Microsoft OpenXPS Class Driver",
        "Microsoft XPS Class Driver"
    )

    foreach ($name in $preferred) {
        if (Get-PrinterDriver -Name $name -ErrorAction SilentlyContinue) {
            return $name
        }
    }

    $fallback = Get-PrinterDriver |
        Where-Object { $_.Name -match "Print To PDF|OpenXPS|XPS Class" } |
        Select-Object -First 1

    if ($fallback) {
        return $fallback.Name
    }

    throw "No PDF or XPS printer driver is available on this PC."
}

function Remove-LegacyPrinterPort {
    param([string]$LegacyPortName)

    if ([string]::IsNullOrWhiteSpace($LegacyPortName)) {
        return
    }

    if (-not (Get-PrinterPort -Name $LegacyPortName -ErrorAction SilentlyContinue)) {
        return
    }

    $existingPrinter = Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue
    if ($existingPrinter -and $existingPrinter.PortName -eq $LegacyPortName) {
        Remove-Printer -Name $PrinterName -ErrorAction SilentlyContinue
    }

    Remove-PrinterPort -Name $LegacyPortName -ErrorAction SilentlyContinue
    Write-Ok "Removed legacy port '$LegacyPortName'"
}

function Install-PrintoCryptPrinter {
    Write-Step "Installing printer '$PrinterName' for all users..."

    $portName = "PrintoCrypt_$Port"
    $incomingPath = Join-Path $env:ProgramData "PrintoCrypt\incoming"
    $legacyFolderPort = if ($incomingPath.EndsWith('\')) { $incomingPath } else { "$incomingPath\" }

    Remove-LegacyPrinterPort -LegacyPortName $legacyFolderPort
    Remove-LegacyPrinterPort -LegacyPortName '\\.\pipe\PrintoCrypt'

    if (-not (Get-PrinterPort -Name $portName -ErrorAction SilentlyContinue)) {
        Add-PrinterPort -Name $portName -PrinterHostAddress $HostAddress -PortNumber $Port
    }

    if (-not (Get-PrinterPort -Name $portName -ErrorAction SilentlyContinue)) {
        throw "Could not create printer port '$portName' on ${HostAddress}:${Port}."
    }

    Write-Ok "Created TCP/IP port ${HostAddress}:${Port}"

    $driverName = Get-PrintDriverName
    Write-Ok "Using driver: $driverName"

    if (Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue) {
        Remove-Printer -Name $PrinterName
    }

    Add-Printer -Name $PrinterName -DriverName $driverName -PortName $portName

    if (-not (Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue)) {
        throw "Printer '$PrinterName' was not created."
    }

    Write-Ok "Printer '$PrinterName' is available to all users on this PC."
}

function Install-PrintoCryptApp {
    param(
        [string]$SourceDir,
        [string]$DestinationDir
    )

    Write-Step "Installing PrintoCrypt to '$DestinationDir'..."

    New-Item -ItemType Directory -Path $DestinationDir -Force | Out-Null

    & robocopy $SourceDir $DestinationDir /MIR /NFL /NDL /NJH /NJS /NC /NS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) {
        throw "File copy failed with robocopy exit code $LASTEXITCODE."
    }

    Copy-Item -Path $PSCommandPath -Destination (Join-Path $DestinationDir "Install.ps1") -Force
    $spoolerScript = Join-Path (Split-Path $PSCommandPath -Parent) "PrintoCrypt-Spooler.ps1"
    if (Test-Path $spoolerScript) {
        Copy-Item -Path $spoolerScript -Destination (Join-Path $DestinationDir "PrintoCrypt-Spooler.ps1") -Force
    }
    $uninstallScript = Join-Path (Split-Path $PSCommandPath -Parent) "Uninstall.ps1"
    if (Test-Path $uninstallScript) {
        Copy-Item -Path $uninstallScript -Destination (Join-Path $DestinationDir "Uninstall.ps1") -Force
    }
    $analyticsScript = Join-Path (Split-Path $PSCommandPath -Parent) "PrintoCrypt-Analytics.ps1"
    if (Test-Path $analyticsScript) {
        Copy-Item -Path $analyticsScript -Destination (Join-Path $DestinationDir "PrintoCrypt-Analytics.ps1") -Force
    }
}

function Update-UserSettings {
    param([string]$AppDataRoot)

    $settingsDir = Join-Path $AppDataRoot "PrintoCrypt"
    $settingsPath = Join-Path $settingsDir "settings.json"
    New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null

    $outputDirectory = Get-InteractiveUserShellFolder -FolderValueName "Personal"
    if ([string]::IsNullOrWhiteSpace($outputDirectory)) {
        $outputDirectory = [System.IO.Path]::Combine(
            [Environment]::GetFolderPath("MyDocuments"),
            "PrintoCrypt")
    }
    else {
        $outputDirectory = Join-Path $outputDirectory "PrintoCrypt"
    }

    $settings = [ordered]@{
        listenPort = $Port
        printerName = $PrinterName
        outputDirectory = $outputDirectory
        openOutputFolderAfterSave = $false
        openOutlookAfterSave = $true
        startWithWindows = $true
    }

    if (Test-Path $settingsPath) {
        try {
            $existing = Get-Content $settingsPath -Raw | ConvertFrom-Json
            if ($existing.outputDirectory) {
                $settings.outputDirectory = [string]$existing.outputDirectory
            }
            if ($null -ne $existing.openOutlookAfterSave) {
                $settings.openOutlookAfterSave = [bool]$existing.openOutlookAfterSave
            }
            if ($null -ne $existing.openOutputFolderAfterSave) {
                $settings.openOutputFolderAfterSave = [bool]$existing.openOutputFolderAfterSave
            }
        }
        catch {
        }
    }

    ($settings | ConvertTo-Json -Depth 4) | Set-Content -Path $settingsPath -Encoding UTF8
    Write-Ok "Updated settings for the logged-on user."
}

function Register-StartupForInteractiveUser {
    param([string]$ExePath)

    $sid = Get-InteractiveUserSid
    if (-not $sid) {
        Write-Host "Could not determine the logged-on user; startup will be configured on first app launch." -ForegroundColor Yellow
        return
    }

    $runKeyPath = "Registry::HKEY_USERS\$sid\Software\Microsoft\Windows\CurrentVersion\Run"
    New-Item -Path $runKeyPath -Force | Out-Null
    Set-ItemProperty -Path $runKeyPath -Name "PrintoCrypt" -Value "`"$ExePath`""
    Write-Ok "Registered PrintoCrypt to start with Windows."
}

function Register-UninstallEntry {
    param(
        [string]$InstallDirectory,
        [string]$ExePath
    )

    $uninstallScript = Join-Path $InstallDirectory "Uninstall.ps1"
    $uninstallKey = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\PrintoCrypt"

    New-Item -Path $uninstallKey -Force | Out-Null
    Set-ItemProperty -Path $uninstallKey -Name "DisplayName" -Value "PrintoCrypt"
    Set-ItemProperty -Path $uninstallKey -Name "DisplayVersion" -Value (Get-PrintoCryptVersionFromExe -ExePath $ExePath)
    Set-ItemProperty -Path $uninstallKey -Name "Publisher" -Value "PrintoCrypt"
    Set-ItemProperty -Path $uninstallKey -Name "InstallLocation" -Value $InstallDirectory
    Set-ItemProperty -Path $uninstallKey -Name "DisplayIcon" -Value $ExePath
    Set-ItemProperty -Path $uninstallKey -Name "UninstallString" -Value "powershell.exe -ExecutionPolicy Bypass -File `"$uninstallScript`""
    Set-ItemProperty -Path $uninstallKey -Name "QuietUninstallString" -Value "powershell.exe -ExecutionPolicy Bypass -File `"$uninstallScript`" -Quiet"
    Set-ItemProperty -Path $uninstallKey -Name "NoModify" -Value 1 -Type DWord
    Set-ItemProperty -Path $uninstallKey -Name "NoRepair" -Value 1 -Type DWord
}

function New-Shortcuts {
    param(
        [string]$ExePath,
        [string]$InstallDirectory
    )

    $shell = New-Object -ComObject WScript.Shell
    $programFolder = Join-Path ([Environment]::GetFolderPath("CommonPrograms")) "PrintoCrypt"
    New-Item -ItemType Directory -Path $programFolder -Force | Out-Null

    $shortcut = $shell.CreateShortcut((Join-Path $programFolder "PrintoCrypt.lnk"))
    $shortcut.TargetPath = $ExePath
    $shortcut.WorkingDirectory = $InstallDirectory
    $shortcut.Description = "PrintoCrypt virtual printer"
    $shortcut.Save()

    $uninstallShortcut = $shell.CreateShortcut((Join-Path $programFolder "Uninstall PrintoCrypt.lnk"))
    $uninstallShortcut.TargetPath = "powershell.exe"
    $uninstallShortcut.Arguments = "-ExecutionPolicy Bypass -File `"$(Join-Path $InstallDirectory 'Uninstall.ps1')`""
    $uninstallShortcut.WorkingDirectory = $InstallDirectory
    $uninstallShortcut.Save()

    Write-Ok "Created Start Menu shortcuts"
}

function Start-PrintoCryptAsUser {
    param([string]$ExePath)

    if (-not (Test-Path $ExePath)) {
        throw "PrintoCrypt executable was not found at '$ExePath'."
    }

    Write-Step "Starting PrintoCrypt in the system tray..."

    try {
        # Launch de-elevated in the interactive desktop session (works from admin installer).
        Start-Process -FilePath "explorer.exe" -ArgumentList "`"$ExePath`""
        Start-Sleep -Seconds 2

        if (Get-Process -Name "PrintoCrypt" -ErrorAction SilentlyContinue) {
            Write-Ok "PrintoCrypt is running in the system tray."
            return
        }
    }
    catch {
        Write-Host "Could not launch via explorer.exe: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    $currentUser = Get-InteractiveUser
    if (-not $currentUser) {
        if (-not $Quiet) {
            Write-Host "PrintoCrypt was installed but could not be started automatically. Open it from the Start Menu." -ForegroundColor Yellow
        }
        return
    }

    $taskName = "PrintoCrypt-Launch"
    schtasks /Delete /TN $taskName /F 2>$null | Out-Null

    $startTime = (Get-Date).AddMinutes(1).ToString("HH:mm")
    $createOutput = schtasks /Create /TN $taskName /TR "`"$ExePath`"" /SC ONCE /ST $startTime /SD (Get-Date -Format "MM/dd/yyyy") /RU $currentUser /RL LIMITED /IT /F 2>&1
    if ($LASTEXITCODE -ne 0) {
        if (-not $Quiet) {
            Write-Host "Could not create launch task: $createOutput" -ForegroundColor Yellow
            Write-Host "Open PrintoCrypt from the Start Menu to start the tray app." -ForegroundColor Yellow
        }
        return
    }

    schtasks /Run /TN $taskName | Out-Null
    Start-Sleep -Seconds 3
    schtasks /Delete /TN $taskName /F 2>$null | Out-Null

    if (Get-Process -Name "PrintoCrypt" -ErrorAction SilentlyContinue) {
        Write-Ok "PrintoCrypt is running in the system tray."
    }
    else {
        if (-not $Quiet) {
            Write-Host "PrintoCrypt was installed but did not start automatically. Open it from the Start Menu." -ForegroundColor Yellow
        }
    }
}

try {
    if (-not $PrinterOnly -and -not $Quiet) {
        Write-Host ""
        Write-Host "PrintoCrypt installer" -ForegroundColor White
        Write-Host "=====================" -ForegroundColor White
        Write-Host ""
    }

    $exePath = Join-Path $InstallDir "PrintoCrypt.exe"

    if (-not $PrinterOnly -and [string]::IsNullOrWhiteSpace($AnalyticsAction)) {
        $installerVersion = "unknown"
        if (-not $SkipAppCopy) {
            $packageRoot = Resolve-PackageRoot
            $sourceAppDir = Resolve-SourceAppDir -Root $packageRoot
            $installerVersion = Get-PrintoCryptVersionFromExe -ExePath (Join-Path $sourceAppDir "PrintoCrypt.exe")
        }
        elseif (Test-Path $exePath) {
            $installerVersion = Get-PrintoCryptVersionFromExe -ExePath $exePath
        }

        if ($installerVersion -ne "unknown") {
            $installIntent = Resolve-InstallAnalyticsAction -InstallDir $InstallDir -InstallerVersion $installerVersion
            if ($installIntent.ShouldSkip) {
                if (-not $Quiet) {
                    Write-Host "PrintoCrypt $installerVersion is already installed." -ForegroundColor Yellow
                }

                Write-Result -Success $true -Message "Already installed."
                exit 0
            }

            $AnalyticsAction = $installIntent.Action
        }
        else {
            $AnalyticsAction = "install"
        }
    }

    if (-not $PrinterOnly -and -not $SkipAppCopy) {
        $packageRoot = Resolve-PackageRoot
        $sourceAppDir = Resolve-SourceAppDir -Root $packageRoot
        Stop-PrintoCryptProcess
        Install-PrintoCryptApp -SourceDir $sourceAppDir -DestinationDir $InstallDir
    }
    elseif (-not $PrinterOnly) {
        Stop-PrintoCryptProcess
    }

    Install-PrintoCryptPrinter

    if (-not $PrinterOnly) {
        Update-UserSettings -AppDataRoot (Get-InteractiveUserAppData)
        Register-StartupForInteractiveUser -ExePath $exePath

        if (-not $SkipAppCopy) {
            Register-UninstallEntry -InstallDirectory $InstallDir -ExePath $exePath
            New-Shortcuts -ExePath $exePath -InstallDirectory $InstallDir
        }

        if (-not $SkipLaunch) {
            Start-PrintoCryptAsUser -ExePath $exePath
        }

        if (-not $Quiet) {
            Write-Host ""
            Write-Ok "PrintoCrypt installed successfully."
            Write-Host "Installed to: $InstallDir"
            Write-Host "Print from any app using the '$PrinterName' printer."
            Write-Host ""
        }

        $message = "PrintoCrypt installed successfully."
    }
    else {
        $message = "Printer '$PrinterName' installed successfully."
        Write-Ok $message
    }

    if (-not $PrinterOnly) {
        Send-PrintoCryptAnalytics -Action $AnalyticsAction -ExePath $exePath
    }

    Write-Result -Success $true -Message $message
}
catch {
    $message = $_.Exception.Message
    Write-Result -Success $false -Message $message
    Show-InstallFailure -Message $message
    exit 1
}
