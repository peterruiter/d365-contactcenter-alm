<#
.SYNOPSIS
    Build the Contact Center ALM code app. Installs dependencies, typechecks, and produces the
    production bundle in app/dist.
.EXAMPLE
    ./build.ps1
.EXAMPLE
    ./build.ps1 -Clean
#>
[CmdletBinding()]
param(
    [switch] $Clean
)

$ErrorActionPreference = 'Stop'
$app = Join-Path $PSScriptRoot 'app'

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
}
finally {
    Pop-Location
}
