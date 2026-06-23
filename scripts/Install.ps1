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
    [switch]$Repair,
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
if (-not (Test-Path $AnalyticsScript)) {
    $AnalyticsScript = Join-Path $InstallDir "PrintoCrypt-Analytics.ps1"
}
if (Test-Path $AnalyticsScript) {
    . $AnalyticsScript
}

$script:InstallLogPath = Join-Path $env:ProgramData "PrintoCrypt\install.log"
$script:PrintoCryptBrokerServiceName = "PrintoCryptBroker"

function Write-InstallLog {
    param([string]$Message)

    $line = "{0:yyyy-MM-dd HH:mm:ss} {1}" -f (Get-Date), $Message
    try {
        $logDir = Split-Path $script:InstallLogPath -Parent
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        Add-Content -Path $script:InstallLogPath -Value $line -Encoding UTF8
    }
    catch {
    }
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
    if ($Quiet) {
        Write-InstallLog "Installation failed: administrator privileges are required."
        exit 1
    }

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

function Test-IsSelfContainedApp {
    param([string]$AppDir)

    if (Test-Path (Join-Path $AppDir "hostfxr.dll")) {
        return $true
    }

    $runtimeConfigPath = Join-Path $AppDir "PrintoCrypt.runtimeconfig.json"
    if (-not (Test-Path $runtimeConfigPath)) {
        return $false
    }

    try {
        $runtimeConfig = Get-Content -Path $runtimeConfigPath -Raw | ConvertFrom-Json
        return $null -ne $runtimeConfig.runtimeOptions.includedFrameworks
    }
    catch {
        return $false
    }
}

function Test-DotNetDesktopRuntimeInstalled {
    param([int]$MajorVersion = 8)

    $registryRoots = @(
        "HKLM:\SOFTWARE\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.WindowsDesktop.App",
        "HKLM:\SOFTWARE\WOW6432Node\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.WindowsDesktop.App"
    )

    foreach ($registryRoot in $registryRoots) {
        if (-not (Test-Path $registryRoot)) {
            continue
        }

        $installedVersions = Get-ChildItem -Path $registryRoot -ErrorAction SilentlyContinue |
            Where-Object { $_.PSChildName -match "^$MajorVersion\." }

        if ($installedVersions) {
            return $true
        }
    }

    return $false
}

function Install-DotNetDesktopRuntime {
    param([int]$MajorVersion = 8)

    Write-Step "Installing .NET $MajorVersion Desktop Runtime..."

    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        & winget install --id "Microsoft.DotNet.DesktopRuntime.$MajorVersion" `
            --accept-package-agreements `
            --accept-source-agreements `
            --silent | Out-Null

        if ($LASTEXITCODE -eq 0 -or (Test-DotNetDesktopRuntimeInstalled -MajorVersion $MajorVersion)) {
            Write-Ok ".NET $MajorVersion Desktop Runtime is installed."
            return
        }
    }

    $installerUrl = "https://aka.ms/dotnet/$MajorVersion.0/windowsdesktopruntime-win-x64.exe"
    $installerPath = Join-Path $env:TEMP "windowsdesktop-runtime-$MajorVersion-win-x64.exe"

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing
    }
    catch {
        throw "Could not download the .NET $MajorVersion Desktop Runtime installer: $($_.Exception.Message)"
    }

    $process = Start-Process -FilePath $installerPath -ArgumentList "/install", "/quiet", "/norestart" -Wait -PassThru
    Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue

    if ($process.ExitCode -notin 0, 1638, 3010) {
        throw "Failed to install the .NET $MajorVersion Desktop Runtime (exit code $($process.ExitCode))."
    }

    Write-Ok ".NET $MajorVersion Desktop Runtime is installed."
}

function Ensure-PrintoCryptRuntime {
    param([string]$AppDir)

    if (Test-IsSelfContainedApp -AppDir $AppDir) {
        return
    }

    if (Test-DotNetDesktopRuntimeInstalled -MajorVersion 8) {
        return
    }

    Install-DotNetDesktopRuntime -MajorVersion 8

    if (-not (Test-DotNetDesktopRuntimeInstalled -MajorVersion 8)) {
        throw "PrintoCrypt requires the .NET 8 Desktop Runtime and automatic installation failed."
    }
}

function Get-InteractiveUser {
    $session = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
    if ($session -and $session.UserName) {
        return $session.UserName
    }

    $explorer = Get-Process -Name explorer -ErrorAction SilentlyContinue |
        Where-Object { $_.SessionId -gt 0 } |
        Sort-Object StartTime -Descending |
        Select-Object -First 1

    if (-not $explorer) {
        return $null
    }

    $process = Get-CimInstance Win32_Process -Filter "ProcessId=$($explorer.Id)" -ErrorAction SilentlyContinue
    if (-not $process) {
        return $null
    }

    $owner = Invoke-CimMethod -InputObject $process -MethodName GetOwner
    if ($owner.ReturnValue -ne 0 -or [string]::IsNullOrWhiteSpace($owner.User)) {
        return $null
    }

    if ($owner.Domain -and $owner.Domain -ne "." -and $owner.Domain -ne $env:COMPUTERNAME) {
        return "$($owner.Domain)\$($owner.User)"
    }

    return "$env:COMPUTERNAME\$($owner.User)"
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
    Stop-Service -Name $script:PrintoCryptBrokerServiceName -Force -ErrorAction SilentlyContinue

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

function Install-PrintoCryptPrinterViaPrintUi {
    param(
        [string]$PrinterName,
        [string]$PortName,
        [string]$DriverName
    )

    $infPath = Get-PrintDriverInfPath
    if (-not $infPath) {
        throw "Could not locate a printer driver INF for PrintUI fallback."
    }

    Write-InstallLog "Installing printer '$PrinterName' via PrintUI fallback."

    $argumentList = @(
        "printui.dll,PrintUIEntry",
        "/if",
        "/b", $PrinterName,
        "/f", $infPath,
        "/r", $PortName,
        "/m", $DriverName,
        "/Z"
    )

    $process = Start-Process -FilePath "rundll32.exe" -ArgumentList $argumentList -Wait -PassThru -WindowStyle Hidden
    if ($process.ExitCode -ne 0) {
        throw "PrintUI printer installation failed with exit code $($process.ExitCode)."
    }
}

function Grant-PrintoCryptPrinterAccess {
    param([string]$PrinterName)

    if (-not (Get-Command Set-Printer -ErrorAction SilentlyContinue)) {
        return
    }

    $setPrinterParams = (Get-Command Set-Printer).Parameters
    if (-not $setPrinterParams.ContainsKey("PermissionSDDL")) {
        Write-InstallLog "Printer ACL update skipped because Set-Printer -PermissionSDDL is unavailable."
        return
    }

    try {
        Set-Printer -Name $PrinterName -PermissionSDDL "O:BAG:DUD:(A;OICI;SWRC;;;AU)(A;OICI;SWRC;;;SY)(A;OICI;SWRC;;;BA)" -ErrorAction Stop
        Write-InstallLog "Granted printer access to authenticated users for '$PrinterName'."
    }
    catch {
        Write-InstallLog "Could not update printer permissions for '$PrinterName': $($_.Exception.Message)"
    }
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

    try {
        Add-Printer -Name $PrinterName -DriverName $driverName -PortName $portName -ErrorAction Stop
    }
    catch {
        Write-InstallLog "Add-Printer failed: $($_.Exception.Message)"
        Install-PrintoCryptPrinterViaPrintUi -PrinterName $PrinterName -PortName $portName -DriverName $driverName
    }

    if (-not (Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue)) {
        throw "Printer '$PrinterName' was not created."
    }

    Grant-PrintoCryptPrinterAccess -PrinterName $PrinterName

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
    $userLaunchScript = Join-Path (Split-Path $PSCommandPath -Parent) "PrintoCrypt-UserLaunch.ps1"
    if (Test-Path $userLaunchScript) {
        Copy-Item -Path $userLaunchScript -Destination (Join-Path $DestinationDir "PrintoCrypt-UserLaunch.ps1") -Force
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

function Get-LoggedOnInteractiveUsers {
    $users = New-Object "System.Collections.Generic.HashSet[string]" ([StringComparer]::OrdinalIgnoreCase)

    Get-Process -Name explorer -ErrorAction SilentlyContinue |
        Where-Object { $_.SessionId -gt 0 } |
        ForEach-Object {
            $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)" -ErrorAction SilentlyContinue
            if (-not $proc) {
                return
            }

            $owner = Invoke-CimMethod -InputObject $proc -MethodName GetOwner
            if ($owner.ReturnValue -ne 0 -or [string]::IsNullOrWhiteSpace($owner.User)) {
                return
            }

            if ($owner.Domain -and $owner.Domain -ne "." -and $owner.Domain -ne $env:COMPUTERNAME) {
                [void]$users.Add("$($owner.Domain)\$($owner.User)")
            }
            else {
                [void]$users.Add("$env:COMPUTERNAME\$($owner.User)")
            }
        }

    return @($users)
}

function Start-PrintoCryptViaExplorer {
    param([string]$ExePath)

    try {
        Start-Process -FilePath "explorer.exe" -ArgumentList "`"$ExePath`"" -ErrorAction Stop
        Start-Sleep -Seconds 2
        return $true
    }
    catch {
        return $false
    }
}

function Start-PrintoCryptForUser {
    param(
        [string]$ExePath,
        [string]$InstallDir,
        [string]$UserName,
        [switch]$AllowExplorerFallback
    )

    $workingDir = if ($InstallDir) { $InstallDir } else { Split-Path $ExePath -Parent }

    if ($AllowExplorerFallback) {
        if (Start-PrintoCryptViaExplorer -ExePath $ExePath) {
            return $true
        }
    }

    $userLauncher = Join-Path $InstallDir "PrintoCrypt-UserLaunch.cmd"
    if (Test-Path $userLauncher) {
        try {
            Start-Process -FilePath $userLauncher -WorkingDirectory $InstallDir -WindowStyle Hidden -ErrorAction Stop | Out-Null
            return $true
        }
        catch {
        }
    }

    return $false
}

function Start-PrintoCryptForLoggedOnUsers {
    param(
        [string]$ExePath,
        [string]$InstallDir
    )

    if (-not (Test-Path $ExePath)) {
        throw "PrintoCrypt executable was not found at '$ExePath'."
    }

    Write-Step "Starting PrintoCrypt for logged-on users..."

    $orderedUsers = New-Object "System.Collections.Generic.List[string]"
    $activeUser = Get-InteractiveUser
    if ($activeUser) {
        [void]$orderedUsers.Add($activeUser)
    }

    foreach ($user in Get-LoggedOnInteractiveUsers) {
        if (-not $orderedUsers.Contains($user)) {
            [void]$orderedUsers.Add($user)
        }
    }

    if ($orderedUsers.Count -eq 0) {
        if (-not $Quiet) {
            Write-Host "No interactive users are logged on. PrintoCrypt will start at the next logon." -ForegroundColor Yellow
        }
        return
    }

    $startedAny = $false
    for ($index = 0; $index -lt $orderedUsers.Count; $index++) {
        $user = $orderedUsers[$index]
        $allowExplorerFallback = ($index -eq 0)

        if (Start-PrintoCryptForUser -ExePath $ExePath -InstallDir $InstallDir -UserName $user -AllowExplorerFallback:$allowExplorerFallback) {
            $startedAny = $true
            Start-Sleep -Seconds 2
        }
    }

    if ($startedAny) {
        Write-Ok "PrintoCrypt started for logged-on users."
        return
    }

    if (-not $Quiet) {
        Write-Host "PrintoCrypt could not be started automatically. It will start at the next user logon." -ForegroundColor Yellow
    }
}

function Test-TcpPortListening {
    param(
        [int]$Port,
        [string]$HostAddress = "127.0.0.1"
    )

    try {
        $listeners = [System.Net.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners()
        foreach ($endpoint in $listeners) {
            if ($endpoint.Port -ne $Port) {
                continue
            }

            $address = $endpoint.Address.ToString()
            if ($address -eq $HostAddress -or $address -eq "0.0.0.0" -or $address -eq "::") {
                return $true
            }
        }
    }
    catch {
    }

    return $false
}

function Get-ScExePath {
    $system32 = Join-Path $env:SystemRoot "System32"
    $candidates = @(
        (Join-Path $system32 "sc.exe"),
        (Join-Path $env:SystemRoot "Sysnative\sc.exe")
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    return "sc.exe"
}

function Invoke-ScExe {
    param([string[]]$ArgumentList)

    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"
    try {
        $scPath = Get-ScExePath
        $output = (& $scPath @ArgumentList 2>&1 | ForEach-Object { "$_" }) -join [Environment]::NewLine
        return @{
            ExitCode = $LASTEXITCODE
            Output   = $output.Trim()
        }
    }
    catch {
        return @{
            ExitCode = 1
            Output   = $_.Exception.Message
        }
    }
    finally {
        $ErrorActionPreference = $previousErrorAction
    }
}

function Invoke-SafeScheduledTaskDelete {
    param([string]$TaskName)

    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"
    try {
        Unregister-ScheduledTask -TaskName $TaskName -TaskPath "\PrintoCrypt\" -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
    }
    catch {
    }

    try {
        $schTasksPath = Join-Path $env:SystemRoot "System32\schtasks.exe"
        if (Test-Path -LiteralPath $schTasksPath) {
            & $schTasksPath /Delete /TN "\PrintoCrypt\$TaskName" /F 2>&1 | Out-Null
        }
    }
    catch {
    }
    finally {
        $ErrorActionPreference = $previousErrorAction
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
            $stopResult = Invoke-CimMethod -InputObject $service -MethodName StopService -ErrorAction SilentlyContinue
            if ($stopResult -and $stopResult.ReturnValue -ne 0) {
                Write-InstallLog "Broker service StopService returned $($stopResult.ReturnValue)."
            }

            Start-Sleep -Seconds 2
        }
    }
    catch {
        Write-InstallLog "Could not stop broker service via CIM: $($_.Exception.Message)"
    }

    try {
        $service = Get-CimInstance Win32_Service -Filter "Name='$($script:PrintoCryptBrokerServiceName)'" -ErrorAction SilentlyContinue
        if ($service) {
            $deleteResult = Invoke-CimMethod -InputObject $service -MethodName Delete -ErrorAction SilentlyContinue
            if ($deleteResult -and $deleteResult.ReturnValue -ne 0) {
                Write-InstallLog "Broker service Delete returned $($deleteResult.ReturnValue); trying sc.exe."
                Invoke-ScExe -ArgumentList @("delete", $script:PrintoCryptBrokerServiceName) | Out-Null
            }
            elseif (-not $deleteResult) {
                Write-InstallLog "Broker service Delete returned no result; trying sc.exe."
                Invoke-ScExe -ArgumentList @("delete", $script:PrintoCryptBrokerServiceName) | Out-Null
            }

            Start-Sleep -Seconds 2
        }
    }
    catch {
        Write-InstallLog "Could not delete broker service: $($_.Exception.Message)"
        Invoke-ScExe -ArgumentList @("delete", $script:PrintoCryptBrokerServiceName) | Out-Null
    }
    finally {
        $ErrorActionPreference = $previousErrorAction
    }
}

function Remove-LegacyPrintoCryptBrokerStartup {
    param([string]$InstallDir)

    Remove-LegacyPrintoCryptScheduledTasks

    $machineRunKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
    if (Test-Path $machineRunKey) {
        Remove-ItemProperty -Path $machineRunKey -Name "PrintoCrypt Broker" -ErrorAction SilentlyContinue
    }

    if ($InstallDir) {
        Remove-Item -Path (Join-Path $InstallDir "PrintoCrypt-BrokerLaunch.cmd") -Force -ErrorAction SilentlyContinue
        Remove-Item -Path (Join-Path $InstallDir "PrintoCrypt-BrokerService.cmd") -Force -ErrorAction SilentlyContinue
    }
}

function Start-PrintoCryptBroker {
    param([int]$Port = 9150)

    Write-Step "Starting PrintoCrypt broker service..."

    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = "Continue"

    try {
        Start-Service -Name $script:PrintoCryptBrokerServiceName -ErrorAction Stop
    }
    catch {
        Write-InstallLog "Start-Service failed: $($_.Exception.Message)"
        $startResult = Invoke-ScExe -ArgumentList @("start", $script:PrintoCryptBrokerServiceName)
        if ($startResult.ExitCode -ne 0 -and $startResult.Output) {
            Write-InstallLog "sc.exe start output: $($startResult.Output)"
        }
    }

    $ErrorActionPreference = $previousErrorAction

    for ($attempt = 0; $attempt -lt 15; $attempt++) {
        if (Test-TcpPortListening -Port $Port) {
            Write-Ok "PrintoCrypt broker is listening on port $Port."
            return $true
        }

        Start-Sleep -Seconds 1
    }

    if (-not $Quiet) {
        Write-Host "PrintoCrypt broker service did not start listening on port $Port." -ForegroundColor Yellow
    }

    Write-InstallLog "Broker service did not open port $Port within 15 seconds."
    return $false
}

function Get-ShortPathSafe {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $Path
    }

    try {
        $fso = New-Object -ComObject Scripting.FileSystemObject
        return $fso.GetFile((Resolve-Path -LiteralPath $Path).Path).ShortPath
    }
    catch {
        return (Resolve-Path -LiteralPath $Path).Path
    }
}

function Get-PrintoCryptBrokerServicePathCandidates {
    param([string]$ExePath)

    if (-not (Test-Path -LiteralPath $ExePath)) {
        throw "PrintoCrypt executable was not found at '$ExePath'."
    }

    $resolvedPath = (Resolve-Path -LiteralPath $ExePath).Path
    $shortPath = Get-ShortPathSafe -Path $resolvedPath
    $candidates = @()

    foreach ($path in @($resolvedPath, $shortPath)) {
        if ([string]::IsNullOrWhiteSpace($path)) {
            continue
        }

        $quoted = """$path"" --broker"
        if ($candidates -notcontains $quoted) {
            $candidates += $quoted
        }

        $unquoted = "$path --broker"
        if ($candidates -notcontains $unquoted) {
            $candidates += $unquoted
        }
    }

    return $candidates
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

function New-PrintoCryptBrokerServiceViaSc {
    param(
        [string]$ServicePath,
        [string]$DisplayName,
        [string]$ExePath = ""
    )

    $binPathVariants = @(
        'binPath= "' + $ServicePath + '"',
        'binPath= ' + $ServicePath
    )

    if (-not [string]::IsNullOrWhiteSpace($ExePath) -and (Test-Path -LiteralPath $ExePath)) {
        $resolvedPath = (Resolve-Path -LiteralPath $ExePath).Path
        $shortPath = Get-ShortPathSafe -Path $resolvedPath
        $binPathVariants += "binPath= $shortPath --broker"
        $binPathVariants += 'binPath= "\"' + $resolvedPath + '\" --broker"'
    }

    foreach ($binPath in ($binPathVariants | Select-Object -Unique)) {
        Write-InstallLog "Trying sc.exe create with $binPath"
        $createResult = Invoke-ScExe -ArgumentList @(
            "create",
            $script:PrintoCryptBrokerServiceName,
            $binPath,
            "start= auto",
            "DisplayName= $DisplayName"
        )

        if ($createResult.ExitCode -eq 0) {
            Write-InstallLog "Created broker service via sc.exe."
            return $true
        }

        Write-InstallLog "sc.exe create failed (exit $($createResult.ExitCode)): $($createResult.Output)"
    }

    return $false
}

function New-PrintoCryptBrokerServiceViaCim {
    param(
        [string]$ServicePath,
        [string]$DisplayName,
        [string]$Description
    )

    $createResult = Invoke-CimMethod -ClassName Win32_Service -MethodName Create -Arguments @{
        Name            = $script:PrintoCryptBrokerServiceName
        DisplayName     = $DisplayName
        PathName        = $ServicePath
        ServiceType     = [byte]16
        ErrorControl    = [byte]1
        StartMode       = "Automatic"
        DesktopInteract = $false
        StartName       = "LocalSystem"
    }

    switch ($createResult.ReturnValue) {
        0 {
            Write-InstallLog "Created broker service via Win32_Service.Create."
            return $true
        }
        1073 {
            Write-InstallLog "Broker service already exists; removing and recreating."
            Stop-PrintoCryptBrokerService
            if (-not (Wait-PrintoCryptBrokerServiceRemoved)) {
                Write-InstallLog "Timed out waiting for existing broker service removal."
                return $false
            }

            $retryResult = Invoke-CimMethod -ClassName Win32_Service -MethodName Create -Arguments @{
                Name            = $script:PrintoCryptBrokerServiceName
                DisplayName     = $DisplayName
                PathName        = $ServicePath
                ServiceType     = [byte]16
                ErrorControl    = [byte]1
                StartMode       = "Automatic"
                DesktopInteract = $false
                StartName       = "LocalSystem"
            }

            if ($retryResult.ReturnValue -eq 0) {
                Write-InstallLog "Recreated broker service via Win32_Service.Create."
                return $true
            }

            Write-InstallLog "Win32_Service.Create retry failed with return code $($retryResult.ReturnValue)."
            return $false
        }
        default {
            Write-InstallLog "Win32_Service.Create failed with return code $($createResult.ReturnValue) for path '$ServicePath'."
            return $false
        }
    }
}
function New-PrintoCryptBrokerServiceWrapper {
    param([string]$InstallDir)

    $wrapperPath = Join-Path $InstallDir "PrintoCrypt-BrokerService.cmd"
    @"
@echo off
cd /d "%~dp0"
"%~dp0PrintoCrypt.exe" --broker
"@ | Set-Content -Path $wrapperPath -Encoding ASCII -Force

    return $wrapperPath
}

function Install-PrintoCryptBrokerService {
    param(
        [string]$ExePath,
        [string]$InstallDir
    )

    if (-not (Test-Path -LiteralPath $ExePath)) {
        throw "PrintoCrypt executable was not found at '$ExePath'."
    }

    Write-InstallLog "Installing broker Windows service for '$ExePath'."

    try {
        Write-InstallLog "Removing any existing PrintoCrypt broker service."
        Stop-PrintoCryptBrokerService
        Wait-PrintoCryptBrokerServiceRemoved | Out-Null

        Write-InstallLog "Removing legacy PrintoCrypt startup entries."
        Remove-LegacyPrintoCryptBrokerStartup -InstallDir $InstallDir
    }
    catch {
        Write-InstallLog "Legacy broker cleanup failed (continuing): $($_.Exception.Message)"
    }

    Write-InstallLog "Building broker service path candidates."
    $servicePathCandidates = Get-PrintoCryptBrokerServicePathCandidates -ExePath $ExePath
    $displayName = "PrintoCrypt Broker"
    $description = "Receives PrintoCrypt print jobs and routes them to logged-on users."

    Write-InstallLog ("Broker service path candidates: {0}" -f ($servicePathCandidates -join " | "))

    $serviceCreated = $false
    $lastError = "Unknown broker service creation failure."
    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = "Continue"

    foreach ($servicePath in $servicePathCandidates) {
        Write-InstallLog "Trying broker service path: $servicePath"

        try {
            if (New-PrintoCryptBrokerServiceViaCim -ServicePath $servicePath -DisplayName $displayName -Description $description) {
                $serviceCreated = $true
                break
            }
        }
        catch {
            $lastError = $_.Exception.Message
            Write-InstallLog "Win32_Service.Create threw: $lastError"
        }

        try {
            New-Service `
                -Name $script:PrintoCryptBrokerServiceName `
                -BinaryPathName $servicePath `
                -DisplayName $displayName `
                -Description $description `
                -StartupType Automatic `
                -ErrorAction Stop | Out-Null
            $serviceCreated = $true
            Write-InstallLog "Created broker service via New-Service."
            break
        }
        catch {
            $lastError = $_.Exception.Message
            Write-InstallLog "New-Service failed for '$servicePath': $lastError"
            Stop-PrintoCryptBrokerService
            Wait-PrintoCryptBrokerServiceRemoved | Out-Null
        }

        if (New-PrintoCryptBrokerServiceViaSc -ServicePath $servicePath -DisplayName $displayName -ExePath $ExePath) {
            $serviceCreated = $true
            break
        }

        Stop-PrintoCryptBrokerService
        Wait-PrintoCryptBrokerServiceRemoved | Out-Null
    }

    $ErrorActionPreference = $previousErrorAction

    if (-not $serviceCreated) {
        throw "Could not create PrintoCrypt broker service. $lastError"
    }

    $descriptionResult = Invoke-ScExe -ArgumentList @(
        "description",
        $script:PrintoCryptBrokerServiceName,
        $description
    )
    if ($descriptionResult.ExitCode -ne 0 -and $descriptionResult.Output) {
        Write-InstallLog "Could not set broker service description: $($descriptionResult.Output)"
    }

    $failureResult = Invoke-ScExe -ArgumentList @(
        "failure",
        $script:PrintoCryptBrokerServiceName,
        "reset= 86400",
        "actions= restart/60000/restart/60000/restart/60000"
    )
    if ($failureResult.ExitCode -ne 0 -and $failureResult.Output) {
        Write-InstallLog "Could not configure broker service recovery: $($failureResult.Output)"
    }

    Write-InstallLog "Installed Windows service '$($script:PrintoCryptBrokerServiceName)'."
}

function Write-MachineSettings {
    param(
        [int]$Port,
        [string]$PrinterName
    )

    $settingsDir = Join-Path $env:ProgramData "PrintoCrypt"
    New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null

    $settings = [ordered]@{
        listenPort  = $Port
        printerName = $PrinterName
    }

    ($settings | ConvertTo-Json -Depth 4) | Set-Content -Path (Join-Path $settingsDir "machine-settings.json") -Encoding UTF8
}

function Ensure-PrintoCryptSupportScripts {
    param([string]$InstallDir)

    foreach ($scriptName in @(
            "PrintoCrypt-UserLaunch.ps1",
            "PrintoCrypt-Analytics.ps1",
            "PrintoCrypt-Spooler.ps1"
        )) {
        $targetPath = Join-Path $InstallDir $scriptName
        if (Test-Path $targetPath) {
            continue
        }

        $sourcePath = Join-Path (Split-Path $PSCommandPath -Parent) $scriptName
        if (-not (Test-Path $sourcePath)) {
            $sourcePath = Join-Path $PSScriptRoot $scriptName
        }

        if (Test-Path $sourcePath) {
            Copy-Item -Path $sourcePath -Destination $targetPath -Force
            Write-InstallLog "Copied missing support script '$scriptName'."
        }
    }
}

function Register-PrintoCryptActiveSetup {
    param(
        [string]$ExePath,
        [string]$InstallDir,
        [string]$UserLauncherPath = ""
    )

    $componentId = "{8F4E2A61-9C3D-4B15-9E7A-1D2F8C6B4A90}"
    $keyPath = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\$componentId"
    $userLaunchScript = Join-Path $InstallDir "PrintoCrypt-UserLaunch.ps1"

    if (-not (Test-Path $userLaunchScript)) {
        Write-InstallLog "Active Setup skipped because PrintoCrypt-UserLaunch.ps1 is missing."
        return
    }

    if ([string]::IsNullOrWhiteSpace($UserLauncherPath)) {
        $UserLauncherPath = Join-Path $InstallDir "PrintoCrypt-UserLaunch.cmd"
    }

    $version = Get-PrintoCryptVersionFromExe -ExePath $ExePath
    if ([string]::IsNullOrWhiteSpace($version) -or $version -eq "unknown") {
        $version = "1.0.1"
    }

    $stubPath = "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$userLaunchScript`""
    New-Item -Path $keyPath -Force | Out-Null
    Set-ItemProperty -Path $keyPath -Name "(default)" -Value "PrintoCrypt"
    Set-ItemProperty -Path $keyPath -Name "Version" -Value ",$version"
    Set-ItemProperty -Path $keyPath -Name "StubPath" -Value $stubPath
    Set-ItemProperty -Path $keyPath -Name "IsInstalled" -Value 1 -Type DWord

    if (Test-Path $UserLauncherPath) {
        $configKey = "HKLM:\SOFTWARE\PrintoCrypt"
        if (-not (Test-Path $configKey)) {
            New-Item -Path $configKey -Force | Out-Null
        }

        Set-ItemProperty -Path $configKey -Name "UserLauncher" -Value $UserLauncherPath -Type String
    }

    Write-InstallLog "Registered Active Setup for per-user launch (version $version)."
    Write-Ok "Registered per-user startup for domain and local accounts."
}

function Remove-LegacyPrintoCryptScheduledTasks {
    Invoke-SafeScheduledTaskDelete -TaskName "PrintoCrypt Broker"
    Invoke-SafeScheduledTaskDelete -TaskName "PrintoCrypt"
}

function New-PrintoCryptLauncherScript {
    param(
        [string]$InstallDir,
        [string]$ScriptName,
        [string]$Arguments = ""
    )

    $scriptPath = Join-Path $InstallDir $ScriptName
    $argumentSuffix = if ([string]::IsNullOrWhiteSpace($Arguments)) { "" } else { " $Arguments" }

    @"
@echo off
cd /d "%~dp0"
start "" /MIN "%~dp0PrintoCrypt.exe"$argumentSuffix
"@ | Set-Content -Path $scriptPath -Encoding ASCII -Force

    return $scriptPath
}

function Register-PrintoCryptRegistryStartup {
    param(
        [string]$ExePath,
        [string]$InstallDir,
        [int]$Port = 9150,
        [string]$PrinterName = "PrintoCrypt"
    )

    Ensure-PrintoCryptSupportScripts -InstallDir $InstallDir
    Write-MachineSettings -Port $Port -PrinterName $PrinterName
    Write-InstallLog "Registering PrintoCrypt startup for '$ExePath'."

    Install-PrintoCryptBrokerService -ExePath $ExePath -InstallDir $InstallDir

    $userLauncher = New-PrintoCryptLauncherScript -InstallDir $InstallDir -ScriptName "PrintoCrypt-UserLaunch.cmd"

    Register-PrintoCryptActiveSetup -ExePath $ExePath -InstallDir $InstallDir -UserLauncherPath $userLauncher
    Start-PrintoCryptBroker -Port $Port

    Write-Ok "Registered PrintoCrypt broker service and per-user startup."
}

function Register-StartupForAllUsers {
    param(
        [string]$ExePath,
        [string]$InstallDir,
        [int]$Port = 9150,
        [string]$PrinterName = "PrintoCrypt"
    )

    Register-PrintoCryptRegistryStartup -ExePath $ExePath -InstallDir $InstallDir -Port $Port -PrinterName $PrinterName
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
    param(
        [string]$ExePath,
        [string]$InstallDir = ""
    )

    if ([string]::IsNullOrWhiteSpace($InstallDir)) {
        $InstallDir = Split-Path $ExePath -Parent
    }

    Start-PrintoCryptForLoggedOnUsers -ExePath $ExePath -InstallDir $InstallDir
}

try {
    if ($Repair) {
        $SkipAppCopy = $true
        Write-InstallLog "Repair mode: reconfiguring PrintoCrypt at '$InstallDir'."
    }
    else {
        Write-InstallLog "Starting PrintoCrypt installation at '$InstallDir'."
    }

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
        Install-PrintoCryptPrinter
        Ensure-PrintoCryptRuntime -AppDir $sourceAppDir
        Install-PrintoCryptApp -SourceDir $sourceAppDir -DestinationDir $InstallDir
    }
    elseif (-not $PrinterOnly) {
        Stop-PrintoCryptProcess
        Install-PrintoCryptPrinter
        Ensure-PrintoCryptRuntime -AppDir $InstallDir
    }
    else {
        Install-PrintoCryptPrinter
    }

    if (-not $PrinterOnly) {
        Update-UserSettings -AppDataRoot (Get-InteractiveUserAppData)
        Register-StartupForAllUsers -ExePath $exePath -InstallDir $InstallDir -Port $Port -PrinterName $PrinterName

        if (-not $SkipAppCopy) {
            Register-UninstallEntry -InstallDirectory $InstallDir -ExePath $exePath
            New-Shortcuts -ExePath $exePath -InstallDirectory $InstallDir
        }

        if (-not $SkipLaunch) {
            Start-PrintoCryptAsUser -ExePath $exePath -InstallDir $InstallDir
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

    if (-not $PrinterOnly -and $AnalyticsAction -in @("install", "update")) {
        if (Get-Command Send-PrintoCryptAnalytics -ErrorAction SilentlyContinue) {
            Send-PrintoCryptAnalytics -Action $AnalyticsAction -ExePath $exePath
        }
    }

    Write-InstallLog $message
    Write-Result -Success $true -Message $message
}
catch {
    $message = $_.Exception.Message
    Write-InstallLog "Installation failed: $message"
    Write-Result -Success $false -Message $message
    Show-InstallFailure -Message $message
    exit 1
}
