<#
.SYNOPSIS
    Build the Contact Center ALM code app. Installs dependencies, typechecks, and produces the
    production bundle in app/dist. Optionally pushes it to a Power Platform environment.
.PARAMETER Deploy
    After a successful build, run 'pac code push' to publish the app.
.PARAMETER EnvironmentUrl
    Only used with -Deploy. Selects this environment first (creating/reusing a pac auth profile
    for it). Omit to push using whatever environment the current pac auth profile is already
    pointed at - the quick path when you are iterating against one environment all session.
.EXAMPLE
    ./build.ps1
.EXAMPLE
    ./build.ps1 -Clean
.EXAMPLE
    ./build.ps1 -Deploy
.EXAMPLE
    ./build.ps1 -Deploy -EnvironmentUrl https://contoso-dev.crm4.dynamics.com
#>
[CmdletBinding()]
param(
    [switch] $Clean,
    [switch] $Deploy,
    [string] $EnvironmentUrl
)

$ErrorActionPreference = 'Stop'
$app = Join-Path $PSScriptRoot 'app'

if ($EnvironmentUrl -and -not $Deploy) {
    throw '-EnvironmentUrl only applies with -Deploy.'
}

if ($Deploy -and $EnvironmentUrl) {
    if (-not (Get-Command pac -ErrorAction SilentlyContinue)) {
        throw "Power Platform CLI (pac) not found. Install it: https://aka.ms/PowerPlatformCLI"
    }
    Write-Host "Selecting environment $EnvironmentUrl" -ForegroundColor Cyan
    pac auth create --url $EnvironmentUrl --name "ccalm-$([guid]::NewGuid().ToString('N').Substring(0,6))" 2>$null
    pac auth select --url $EnvironmentUrl
    pac org who
}

Push-Location $app
try {
    if ($Clean) {
        Write-Host 'Cleaning node_modules and dist' -ForegroundColor DarkGray
        Remove-Item -Recurse -Force node_modules, dist -ErrorAction SilentlyContinue
    }

    if (-not (Test-Path 'node_modules')) {
        Write-Host 'Installing dependencies' -ForegroundColor Cyan
        npm ci
        if ($LASTEXITCODE -ne 0) { npm install }
    }

    Write-Host 'Typecheck' -ForegroundColor Cyan
    npm run typecheck
    if ($LASTEXITCODE -ne 0) { throw 'Typecheck failed.' }

    Write-Host 'Build' -ForegroundColor Cyan
    npm run build
    if ($LASTEXITCODE -ne 0) { throw 'Build failed.' }

    Write-Host "Done. Bundle in $app/dist" -ForegroundColor Green

    if ($Deploy) {
        if (-not (Get-Command pac -ErrorAction SilentlyContinue)) {
            throw "Power Platform CLI (pac) not found. Install it: https://aka.ms/PowerPlatformCLI"
        }
        if (-not (Test-Path 'power.config.json')) {
            Write-Warning "No code app config found. Run 'pac code init' once in ./app to create it, then re-run with -Deploy."
            Write-Host "  cd app; pac code init --displayName 'Contact Center ALM'" -ForegroundColor DarkGray
            return
        }
        Write-Host 'Pushing code app' -ForegroundColor Cyan
        pac code push
        if ($LASTEXITCODE -ne 0) { throw 'pac code push failed.' }
        Write-Host 'Published. Open it from Power Apps -> Apps.' -ForegroundColor Green
    }
}
finally {
    Pop-Location
}
