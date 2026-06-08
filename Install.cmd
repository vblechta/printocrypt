@echo off
setlocal

set "SCRIPT=%~dp0Install.ps1"
if not exist "%SCRIPT%" set "SCRIPT=%~dp0scripts\Install.ps1"

if not exist "%SCRIPT%" (
    echo Could not find Install.ps1.
    echo Build the setup package first: powershell -ExecutionPolicy Bypass -File scripts\Build-Installer.ps1
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
set "EXITCODE=%ERRORLEVEL%"
if not "%EXITCODE%"=="0" exit /b %EXITCODE%

endlocal
