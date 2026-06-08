@echo off
setlocal

set "SCRIPT=%~dp0Uninstall.ps1"
if not exist "%SCRIPT%" set "SCRIPT=%~dp0scripts\Uninstall.ps1"
if not exist "%SCRIPT%" set "SCRIPT=%ProgramFiles%\PrintoCrypt\Uninstall.ps1"

if not exist "%SCRIPT%" (
    echo Could not find Uninstall.ps1.
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
set "EXITCODE=%ERRORLEVEL%"
if not "%EXITCODE%"=="0" exit /b %EXITCODE%

endlocal
