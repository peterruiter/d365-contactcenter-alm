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

    Needs PowerShell 7. From a clone of the repo it also builds the app, which needs Node.js; the
    localrunner release zip ships the app pre-built and needs nothing else.
.PARAMETER ProfileName
    Which set of environments to use. One per client, e.g. -Profile contoso.
.PARAMETER Port
    Local port. Default 7171.
.PARAMETER Rebuild
    Rebuild the app even if the build looks current (repo clone only).
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

# No #Requires: Windows PowerShell 5.1 would stop on it with a message that does not say what to do.
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host 'The local runner needs PowerShell 7 (this is Windows PowerShell 5.1).' -ForegroundColor Red
    Write-Host 'Install it:   winget install --id Microsoft.PowerShell -e'
    Write-Host '         or:  https://aka.ms/powershell-release?tag=stable'
    Write-Host 'Then run this from a new "pwsh" window, or double-click Start-LocalRunner.cmd.'
    exit 1
}

$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$appDir = Join-Path $repo 'app'
$staticDir = [IO.Path]::GetFullPath((Join-Path $appDir 'dist-runner'))

# --- Build the app in runner mode when the source is newer than the build -------------------------
# Only in a repo clone. The release zip has the built app and no source, so it never builds and
# never needs Node.js or network access to npm.

$index = Join-Path $staticDir 'index.html'
$hasSource = Test-Path (Join-Path $appDir 'src')
if (-not $hasSource -and -not (Test-Path $index)) {
    throw "The app is missing from $staticDir. Download the localrunner release zip again: https://github.com/peterruiter/d365-contactcenter-alm/releases/tag/localrunner"
}
$needsBuild = $hasSource -and ($Rebuild -or -not (Test-Path $index))
if ($hasSource -and -not $needsBuild) {
    $built = (Get-Item $index).LastWriteTimeUtc
    $newer = Get-ChildItem (Join-Path $appDir 'src'), (Join-Path $appDir 'index.html'), (Join-Path $appDir '.env.runner') -Recurse -File |
        Where-Object { $_.LastWriteTimeUtc -gt $built } | Select-Object -First 1
    $needsBuild = [bool]$newer
}
if ($needsBuild) {
    $noBuild = 'No Node.js or no access to the npm registry? Use the ready-built localrunner release zip instead: https://github.com/peterruiter/d365-contactcenter-alm/releases/tag/localrunner'
    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) { throw "npm not found. Install Node.js LTS and open a new terminal. $noBuild" }
    Push-Location $appDir
    try {
        if (-not (Test-Path 'node_modules')) {
            Write-Host 'Installing app dependencies (first run)...'
            npm install --no-fund --no-audit
            if ($LASTEXITCODE) { throw "npm install failed. $noBuild" }
        }
        Write-Host 'Building the app for the local runner...'
        npm run build:runner
        if ($LASTEXITCODE) { throw "App build failed. See the output above. $noBuild" }
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
