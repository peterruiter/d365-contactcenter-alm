#Requires -Version 7.2
<#
.SYNOPSIS
    Builds the local runner release zip: everything run-local.ps1 needs, with the app pre-built, so
    whoever unzips it needs only PowerShell 7 - no Node.js, no npm, no git.
.PARAMETER OutputDir
    Where the zip goes. Default ./out.
.EXAMPLE
    ./scripts/build-runner-release.ps1
    gh release upload localrunner ./out/ContactCenterALM-LocalRunner.zip --clobber
#>
[CmdletBinding()]
param(
    [string] $OutputDir = (Join-Path (Split-Path $PSScriptRoot -Parent) 'out')
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$name = 'ContactCenterALM-LocalRunner'

Push-Location (Join-Path $repo 'app')
try {
    if (-not (Test-Path 'node_modules')) { npm ci --no-fund --no-audit; if ($LASTEXITCODE) { throw 'npm ci failed.' } }
    if (Test-Path 'dist-runner') { Remove-Item 'dist-runner' -Recurse -Force }
    npm run build:runner
    if ($LASTEXITCODE) { throw 'App build failed.' }
}
finally { Pop-Location }

# Same layout as the repo, so run-local.ps1 finds everything by its usual relative paths. No app
# source: run-local.ps1 sees that and never tries to build.
$stage = Join-Path ([IO.Path]::GetTempPath()) "$name-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$root = Join-Path $stage $name
$copy = @(
    'Start-LocalRunner.cmd'
    'LICENSE'
    'scripts/run-local.ps1'
    'backend/local-runner'
    'backend/function-app/Contract.ps1'
    'backend/function-app/Modules'
    'config/manifest.json'
    'app/dist-runner'
    'docs/local-runner.md'
)
foreach ($item in $copy) {
    $src = Join-Path $repo $item
    $dst = Join-Path $root $item
    New-Item -ItemType Directory -Path (Split-Path $dst -Parent) -Force | Out-Null
    Copy-Item $src $dst -Recurse
}

$version = (git -C $repo rev-parse --short HEAD)
@"
Contact Center ALM - local runner (build $version)

1. Install PowerShell 7 if you do not have it:  winget install --id Microsoft.PowerShell -e
2. Double-click Start-LocalRunner.cmd and give a profile name (one per client).
3. The browser opens on Setup. Enter each environment's URL, tenant ID, client ID and client
   secret value from the client's app registration, and run the checks.

Nothing else to install. Settings and secrets are stored per profile in
%LOCALAPPDATA%\CcAlm\<profile>, secrets encrypted for your Windows user.

Full guide: docs\local-runner.md
Project:    https://github.com/peterruiter/d365-contactcenter-alm
"@ | Set-Content (Join-Path $root 'README.txt') -Encoding UTF8

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$zip = Join-Path $OutputDir "$name.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path $root -DestinationPath $zip
Remove-Item $stage -Recurse -Force

$size = '{0:N1} MB' -f ((Get-Item $zip).Length / 1MB)
Write-Host "Built $zip ($size, build $version)" -ForegroundColor Green
