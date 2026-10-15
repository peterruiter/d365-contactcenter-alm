@echo off
rem Double-click launcher for the Contact Center ALM local runner (scripts\run-local.ps1).
rem Needs PowerShell 7. -ExecutionPolicy Bypass because a downloaded zip marks every script as
rem coming from the internet, which the default policy refuses to run.
setlocal
cd /d "%~dp0"

where pwsh >nul 2>nul
if errorlevel 1 (
    echo The local runner needs PowerShell 7.
    echo.
    echo Install it:   winget install --id Microsoft.PowerShell -e
    echo          or:  https://aka.ms/powershell-release?tag=stable
    echo.
    echo Then double-click this file again.
    pause
    exit /b 1
)

set "CCALM_PROFILE="
set /p "CCALM_PROFILE=Profile name - one per client (Enter for 'default'): "
if "%CCALM_PROFILE%"=="" set "CCALM_PROFILE=default"

pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\run-local.ps1" -Profile "%CCALM_PROFILE%"
pause
