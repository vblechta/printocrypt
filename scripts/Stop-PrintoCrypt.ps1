#Requires -Version 5.1
$ErrorActionPreference = "SilentlyContinue"

$serviceName = "PrintoCryptBroker"

Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
Get-Process -Name "PrintoCrypt" -ErrorAction SilentlyContinue | Stop-Process -Force

& sc.exe stop $serviceName 2>$null | Out-Null
& sc.exe delete $serviceName 2>$null | Out-Null

for ($attempt = 0; $attempt -lt 30; $attempt++) {
    & sc.exe query $serviceName 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        break
    }

    Start-Sleep -Seconds 1
}

Get-Process -Name "PrintoCrypt" -ErrorAction SilentlyContinue | Stop-Process -Force

exit 0
