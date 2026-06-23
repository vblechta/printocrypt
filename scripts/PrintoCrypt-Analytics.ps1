if ($PSScriptRoot) {
    $PrintoCryptAnalyticsScriptPath = Join-Path $PSScriptRoot "PrintoCrypt-Analytics.ps1"
}
else {
    $PrintoCryptAnalyticsScriptPath = $MyInvocation.MyCommand.Path
}

function Get-PrintoCryptVersionFromExe {
    param([string]$ExePath)

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

    $plusIndex = $version.IndexOf('+')
    if ($plusIndex -ge 0) {
        $version = $version.Substring(0, $plusIndex)
    }

    return $version
}

function Test-IsRunningAsSystem {
    if ($env:USERNAME -eq "SYSTEM") {
        return $true
    }

    $process = Get-CimInstance Win32_Process -Filter "ProcessId=$PID" -ErrorAction SilentlyContinue
    if (-not $process) {
        return $false
    }

    $owner = Invoke-CimMethod -InputObject $process -MethodName GetOwner -ErrorAction SilentlyContinue
    return $owner.User -eq "SYSTEM"
}

function Get-InteractiveUserForAnalytics {
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

function New-PrintoCryptAnalyticsPayload {
    param(
        [Parameter(Mandatory)]
        [ValidateSet("install", "update", "uninstall", "usage")]
        [string]$Action,

        [string]$Version,
        [string]$ExePath
    )

    if ([string]::IsNullOrWhiteSpace($Version)) {
        $Version = Get-PrintoCryptVersionFromExe -ExePath $ExePath
    }

    $publicIp = "unknown"
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        [System.Net.WebRequest]::DefaultWebProxy = $null
        $publicIp = (Invoke-RestMethod -Uri "https://api.ipify.org" -TimeoutSec 5).Trim()
    }
    catch {
    }

    return (@{
        ip        = $publicIp
        hostname  = $env:COMPUTERNAME
        version   = $Version
        action    = $Action
        timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    } | ConvertTo-Json -Compress)
}

function Invoke-PrintoCryptAnalyticsRequest {
    param([string]$BodyJson)

    $analyticsUrl = "https://analytics.printocrypt.ethercloud.io/api/install"
    $apiKey = "B9ZwseWGrQNmcHOuYZjuiVftVAk01w"

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        [System.Net.WebRequest]::DefaultWebProxy = $null

        Invoke-RestMethod `
            -Uri $analyticsUrl `
            -Method Post `
            -Headers @{
                "Content-Type" = "application/json"
                "X-API-Key"    = $apiKey
            } `
            -Body $BodyJson `
            -TimeoutSec 10 | Out-Null

        return $true
    }
    catch {
    }

    $bodyFile = $null
    try {
        if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) {
            return $false
        }

        $bodyFile = [System.IO.Path]::GetTempFileName()
        Set-Content -Path $bodyFile -Value $BodyJson -Encoding UTF8 -NoNewline

        & curl.exe -s -S -f `
            -X POST `
            -H "Content-Type: application/json" `
            -H "X-API-Key: $apiKey" `
            --data-binary "@$bodyFile" `
            $analyticsUrl | Out-Null

        return ($LASTEXITCODE -eq 0)
    }
    catch {
        return $false
    }
    finally {
        if ($bodyFile -and (Test-Path $bodyFile)) {
            Remove-Item -Path $bodyFile -Force -ErrorAction SilentlyContinue
        }
    }
}

function Test-ShouldDeferAnalyticsToInteractiveUser {
    if (Test-IsRunningAsSystem) {
        return $true
    }

    $interactiveUser = Get-InteractiveUserForAnalytics
    if (-not $interactiveUser) {
        return $false
    }

    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    if ($currentUser.Equals($interactiveUser, [StringComparison]::OrdinalIgnoreCase)) {
        return $false
    }

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-InInteractiveUserSession {
    param(
        [Parameter(Mandatory)]
        [string]$UserName,

        [Parameter(Mandatory)]
        [string]$Execute,

        [string]$Arguments = "",
        [string]$WorkingDirectory = "",
        [int]$WaitSeconds = 3
    )

    $taskName = "PrintoCrypt-Run-$([guid]::NewGuid().ToString('N'))"

    try {
        $actionParams = @{
            Execute = $Execute
        }

        if (-not [string]::IsNullOrWhiteSpace($Arguments)) {
            $actionParams.Argument = $Arguments
        }

        if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
            $actionParams.WorkingDirectory = $WorkingDirectory
        }

        $action = New-ScheduledTaskAction @actionParams
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(2)
        $principal = New-ScheduledTaskPrincipal -UserId $UserName -LogonType Interactive -RunLevel Limited
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

        Register-ScheduledTask `
            -TaskName $taskName `
            -Action $action `
            -Trigger $trigger `
            -Principal $principal `
            -Settings $settings `
            -Force | Out-Null

        Start-ScheduledTask -TaskName $taskName | Out-Null
        Start-Sleep -Seconds $WaitSeconds
        return $true
    }
    catch {
        return $false
    }
    finally {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    }
}

function Send-PrintoCryptAnalyticsViaInteractiveUser {
    param(
        [string]$BodyJson,
        [string]$AnalyticsScriptPath
    )

    $user = Get-InteractiveUserForAnalytics
    if (-not $user) {
        return $false
    }

    if (-not (Test-Path $AnalyticsScriptPath)) {
        return $false
    }

    $payloadBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($BodyJson))
    $taskScript = Join-Path $env:TEMP "PrintoCrypt-Analytics-$([guid]::NewGuid().ToString('N')).ps1"
    $escapedAnalyticsScriptPath = $AnalyticsScriptPath.Replace("'", "''")

    @"
#Requires -Version 5.1
`$bodyJson = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$payloadBase64'))
. '$escapedAnalyticsScriptPath'
Invoke-PrintoCryptAnalyticsRequest -BodyJson `$bodyJson | Out-Null
"@ | Set-Content -Path $taskScript -Encoding UTF8

    try {
        return Invoke-InInteractiveUserSession `
            -UserName $user `
            -Execute "powershell.exe" `
            -Arguments "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$taskScript`"" `
            -WaitSeconds 8
    }
    finally {
        Remove-Item -Path $taskScript -Force -ErrorAction SilentlyContinue
    }
}

function Send-PrintoCryptAnalytics {
    param(
        [Parameter(Mandatory)]
        [ValidateSet("install", "update", "uninstall", "usage")]
        [string]$Action,

        [string]$Version,
        [string]$ExePath
    )

    $analyticsScriptPath = $PrintoCryptAnalyticsScriptPath
    if ([string]::IsNullOrWhiteSpace($analyticsScriptPath) -or -not (Test-Path $analyticsScriptPath)) {
        $analyticsScriptPath = Join-Path $PSScriptRoot "PrintoCrypt-Analytics.ps1"
    }

    try {
        $bodyJson = New-PrintoCryptAnalyticsPayload -Action $Action -Version $Version -ExePath $ExePath

        if (Test-ShouldDeferAnalyticsToInteractiveUser) {
            if (Send-PrintoCryptAnalyticsViaInteractiveUser -BodyJson $bodyJson -AnalyticsScriptPath $analyticsScriptPath) {
                return
            }
        }

        Invoke-PrintoCryptAnalyticsRequest -BodyJson $bodyJson | Out-Null
    }
    catch {
    }
}
