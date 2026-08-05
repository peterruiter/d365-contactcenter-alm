<#
.SYNOPSIS
    Publish the code app to a Power Platform environment. Authenticates, selects the environment,
    builds, and pushes.
.DESCRIPTION
    Uses the Power Platform CLI (pac). The environment must have Code Apps enabled
    (admin center -> environment -> Settings -> Product -> Features -> Power Apps code apps).
    Note: Microsoft is moving these commands to the npm-based CLI shipped in @microsoft/power-apps.
    'pac code push' still works today and is used here.
.PARAMETER EnvironmentUrl
    The target environment org URL, e.g. https://contoso-dev.crm4.dynamics.com
.EXAMPLE
    ./scripts/deploy.ps1 -EnvironmentUrl https://contoso-dev.crm4.dynamics.com
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $EnvironmentUrl
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$app = Join-Path $root 'app'

# 1. Confirm pac is available.
if (-not (Get-Command pac -ErrorAction SilentlyContinue)) {
    throw "Power Platform CLI (pac) not found. Install it: https://aka.ms/PowerPlatformCLI"
}

# 2. Auth. Reuses an existing profile if one matches, otherwise opens a browser.
Write-Host "Selecting environment $EnvironmentUrl" -ForegroundColor Cyan
pac auth create --url $EnvironmentUrl --name "ccalm-$([guid]::NewGuid().ToString('N').Substring(0,6))" 2>$null
pac auth select --url $EnvironmentUrl
pac org who

# 3. Build.
Write-Host 'Building app' -ForegroundColor Cyan
& (Join-Path $root 'build.ps1')

# 4. Push the code app.
Push-Location $app
try {
    if (-not (Test-Path 'power.config.json') -and -not (Test-Path 'PowerAppsCode')) {
        Write-Warning "No code app config found. Run 'pac code init' once in ./app to create it, then re-run deploy."
        Write-Host "  cd app; pac code init --displayName 'Contact Center ALM'" -ForegroundColor DarkGray
        return
    }
    Write-Host 'Pushing code app' -ForegroundColor Cyan
    pac code push
    Write-Host 'Published. Open it from Power Apps -> Apps.' -ForegroundColor Green
}
finally {
    Pop-Location
}
