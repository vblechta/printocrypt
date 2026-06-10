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

    return $version
}

function Send-PrintoCryptAnalytics {
    param(
        [Parameter(Mandatory)]
        [ValidateSet("install", "update", "uninstall", "usage")]
        [string]$Action,

        [string]$Version,
        [string]$ExePath
    )

    $analyticsUrl = "https://analytics.printocrypt.ethercloud.io/api/install"
    $apiKey = "B9ZwseWGrQNmcHOuYZjuiVftVAk01w"

    if ([string]::IsNullOrWhiteSpace($Version)) {
        $Version = Get-PrintoCryptVersionFromExe -ExePath $ExePath
    }

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        $publicIp = "unknown"
        try {
            $publicIp = (Invoke-RestMethod -Uri "https://api.ipify.org" -TimeoutSec 5).Trim()
        }
        catch {
        }

        $body = @{
            ip        = $publicIp
            hostname  = $env:COMPUTERNAME
            version   = $Version
            action    = $Action
            timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        } | ConvertTo-Json -Compress

        Invoke-RestMethod `
            -Uri $analyticsUrl `
            -Method Post `
            -Headers @{
                "Content-Type" = "application/json"
                "X-API-Key"    = $apiKey
            } `
            -Body $body `
            -TimeoutSec 10 | Out-Null
    }
    catch {
    }
}
