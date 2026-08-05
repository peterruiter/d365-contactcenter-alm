<#
.SYNOPSIS
    One-time setup for the code app: initialise the Power Apps code app config and add data sources.
.DESCRIPTION
    Run this once per clone. It creates the code app config (power.config.json) via 'pac code init'
    and adds the data source the app calls. For the backend variant, that is the custom connector
    to the ALM backend. For a same-environment build, it is the Dataverse connector.
.PARAMETER EnvironmentUrl
    The environment to initialise against.
.PARAMETER DisplayName
    App display name shown in Power Apps.
.EXAMPLE
    ./scripts/init-app.ps1 -EnvironmentUrl https://contoso-dev.crm4.dynamics.com
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $EnvironmentUrl,
    [string] $DisplayName = 'Contact Center ALM'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$app = Join-Path $root 'app'

if (-not (Get-Command pac -ErrorAction SilentlyContinue)) {
    throw "Power Platform CLI (pac) not found. Install it: https://aka.ms/PowerPlatformCLI"
}

pac auth create --url $EnvironmentUrl --name "ccalm-init" 2>$null
pac auth select --url $EnvironmentUrl

Push-Location $app
try {
    if (-not (Test-Path 'node_modules')) { npm install }

    Write-Host "Initialising code app '$DisplayName'" -ForegroundColor Cyan
    pac code init --displayName $DisplayName

    Write-Host ''
    Write-Host 'Next: add the data source the app calls.' -ForegroundColor Yellow
    Write-Host '  Backend variant (recommended for cross-environment writes):' -ForegroundColor DarkGray
    Write-Host '    pac connector create ... then: pac code add-data-source --apiId <custom-connector-id>' -ForegroundColor DarkGray
    Write-Host '  Same-environment variant:' -ForegroundColor DarkGray
    Write-Host '    pac code add-data-source --apiId /providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host 'Then run locally with mock data:  npm run dev' -ForegroundColor Green
    Write-Host 'Or push it:                       ../scripts/deploy.ps1 -EnvironmentUrl ' -NoNewline -ForegroundColor Green
    Write-Host $EnvironmentUrl -ForegroundColor Green
}
finally {
    Pop-Location
}
