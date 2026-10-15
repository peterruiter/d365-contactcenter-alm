#Requires -Version 7.2
<#
.SYNOPSIS
    Builds the local runner release assets, both with the app pre-built:
      ContactCenterALM-LocalRunner.zip  the runner files; needs PowerShell 7 and nothing else
      ContactCenterALM-LocalRunner.exe  one self-contained file with .NET and PowerShell 7 inside;
                                        needs nothing at all
.PARAMETER OutputDir
    Where the assets go. Default ./out.
.PARAMETER SkipExe
    Only build the zip (the exe needs the .NET 10 SDK).
.EXAMPLE
    ./scripts/build-runner-release.ps1
    gh release upload localrunner ./out/ContactCenterALM-LocalRunner.zip ./out/ContactCenterALM-LocalRunner.exe --clobber
#>
[CmdletBinding()]
param(
    [string] $OutputDir = (Join-Path (Split-Path $PSScriptRoot -Parent) 'out'),
    [switch] $SkipExe
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
Write-Host "Built $zip ($('{0:N1} MB' -f ((Get-Item $zip).Length / 1MB)), build $version)" -ForegroundColor Green

if (-not $SkipExe) {
    # The same files, without the top folder or the launcher, embedded in the exe.
    $exeProject = Join-Path $repo 'runner-exe'
    $payloadDir = Join-Path $exeProject 'payload'
    New-Item -ItemType Directory -Path $payloadDir -Force | Out-Null
    $payload = Join-Path $payloadDir 'payload.zip'
    if (Test-Path $payload) { Remove-Item $payload -Force }
    Remove-Item (Join-Path $root 'Start-LocalRunner.cmd')
    Compress-Archive -Path (Join-Path $root '*') -DestinationPath $payload

    $publishDir = Join-Path $stage 'exe'
    dotnet publish $exeProject -c Release -o $publishDir -p:InformationalVersion=$version --nologo -v quiet
    if ($LASTEXITCODE) { throw 'dotnet publish failed.' }
    $exe = Join-Path $OutputDir "$name.exe"
    Copy-Item (Join-Path $publishDir "$name.exe") $exe -Force
    Write-Host "Built $exe ($('{0:N1} MB' -f ((Get-Item $exe).Length / 1MB)), build $version)" -ForegroundColor Green
}

Remove-Item $stage -Recurse -Force
