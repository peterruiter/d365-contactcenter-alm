#Requires -Version 7.2
<#
.SYNOPSIS
    Runs Contact Center ALM on your own machine: the app plus the engine, talking straight to the
    client's environments with the app registrations they gave you. No Azure, no connector.
.DESCRIPTION
    Starts a small web server on http://localhost:<Port> that serves the app and runs the engine in
    this PowerShell session. The app opens on Setup, where you enter each environment's URL, tenant
    ID, client ID and secret and run the checks one by one. Environments that pass show up in
    Compare.

    Settings live per profile outside the repo (%LOCALAPPDATA%\CcAlm\<profile>), secrets encrypted
    with Windows DPAPI for your user. Use one profile per client.
.PARAMETER ProfileName
    Which set of environments to use. One per client, e.g. -Profile contoso.
.PARAMETER Port
    Local port. Default 7171.
.PARAMETER Rebuild
    Rebuild the app even if the build looks current.
.PARAMETER NoBrowser
    Do not open the browser.
.EXAMPLE
    ./scripts/run-local.ps1 -Profile contoso
#>
[CmdletBinding()]
param(
    [Alias('Profile')] [string] $ProfileName = 'default',
    [int] $Port = 7171,
    [switch] $Rebuild,
    [switch] $NoBrowser
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$appDir = Join-Path $repo 'app'
$staticDir = [IO.Path]::GetFullPath((Join-Path $appDir 'dist-runner'))

# --- Build the app in runner mode when the source is newer than the build -------------------------

$index = Join-Path $staticDir 'index.html'
$needsBuild = $Rebuild -or -not (Test-Path $index)
if (-not $needsBuild) {
    $built = (Get-Item $index).LastWriteTimeUtc
    $newer = Get-ChildItem (Join-Path $appDir 'src'), (Join-Path $appDir 'index.html'), (Join-Path $appDir '.env.runner') -Recurse -File |
        Where-Object { $_.LastWriteTimeUtc -gt $built } | Select-Object -First 1
    $needsBuild = [bool]$newer
}
if ($needsBuild) {
    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) { throw 'npm not found. Install Node.js LTS, open a new terminal, and run this again.' }
    Push-Location $appDir
    try {
        if (-not (Test-Path 'node_modules')) {
            Write-Host 'Installing app dependencies (first run)...'
            npm install --no-fund --no-audit
            if ($LASTEXITCODE) { throw 'npm install failed.' }
        }
        Write-Host 'Building the app for the local runner...'
        npm run build:runner
        if ($LASTEXITCODE) { throw 'App build failed. See the output above.' }
    }
    finally { Pop-Location }
}

# --- Engine, contract mappers, runner ------------------------------------------------------------

$env:CCALM_MANIFEST_PATH = Join-Path $repo 'config/manifest.json'
Import-Module (Join-Path $repo 'backend/function-app/Modules/CcAlm/CcAlm.psd1') -Force
. (Join-Path $repo 'backend/function-app/Contract.ps1')
. (Join-Path $repo 'backend/local-runner/Store.ps1')
. (Join-Path $repo 'backend/local-runner/Checks.ps1')
. (Join-Path $repo 'backend/local-runner/Server.ps1')

Initialize-CcStore $ProfileName
Write-Host "Profile '$ProfileName' stored in $script:CcStoreDir"
if (-not $IsWindows) {
    Write-Warning 'No Windows DPAPI on this OS: secrets are kept in memory only and must be re-entered after a restart.'
}

Start-CcLocalRunner -Port $Port -StaticDir $staticDir -OpenBrowser:(-not $NoBrowser)
