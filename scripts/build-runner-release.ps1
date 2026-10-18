#Requires -Version 7.2
<#
.SYNOPSIS
    Builds the local runner release assets, both with the app pre-built:
      ContactCenterALM-LocalRunner.zip  the runner files; needs PowerShell 7 and nothing else
      ContactCenterALM-LocalRunner.exe  one self-contained file with .NET and PowerShell 7 inside;
                                        needs nothing at all
      build.json                        which build this is; runners compare it with their own to
                                        offer an update, so upload it with the other two
.PARAMETER OutputDir
    Where the assets go. Default ./out.
.PARAMETER SkipExe
    Only build the zip (the exe needs the .NET 10 SDK).
.EXAMPLE
    ./scripts/build-runner-release.ps1
    gh release upload localrunner ./out/ContactCenterALM-LocalRunner.zip ./out/ContactCenterALM-LocalRunner.exe ./out/build.json --clobber
#>
[CmdletBinding()]
param(
    [string] $OutputDir = (Join-Path (Split-Path $PSScriptRoot -Parent) 'out'),
    [switch] $SkipExe
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$name = 'ContactCenterALM-LocalRunner'

# One build identity for the app, the exe and build.json. The build number is the commit count on
# the branch, so a later release always has a higher one.
$pkg = Get-Content (Join-Path $repo 'app/package.json') -Raw | ConvertFrom-Json
$buildInfo = [ordered]@{
    version = $pkg.version
    build   = [int](git -C $repo rev-list --count HEAD)
    commit  = (git -C $repo rev-parse --short HEAD)
    builtAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
}
if (git -C $repo status --porcelain --untracked-files=no -- app/src backend config scripts runner-exe) {
    Write-Warning 'There are uncommitted changes: this build carries the number of the last commit, not of what is built.'
}
$env:CCALM_BUILD_VERSION = $buildInfo.version
$env:CCALM_BUILD_NUMBER = $buildInfo.build
$env:CCALM_BUILD_COMMIT = $buildInfo.commit
$env:CCALM_BUILD_AT = $buildInfo.builtAt
$version = "$($buildInfo.version) build $($buildInfo.build) ($($buildInfo.commit))"

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

@"
Contact Center ALM - local runner, version $version

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
$buildInfo | ConvertTo-Json | Set-Content (Join-Path $OutputDir 'build.json') -Encoding utf8NoBOM
$zip = Join-Path $OutputDir "$name.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path $root -DestinationPath $zip
Write-Host "Built $zip ($('{0:N1} MB' -f ((Get-Item $zip).Length / 1MB)), version $version)" -ForegroundColor Green

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
    # The build's identity in the exe's file properties too: the file version carries the build
    # number, the product version the commit, so an exe on a laptop can be traced back to a commit.
    dotnet publish $exeProject -c Release -o $publishDir --nologo -v quiet `
        -p:Version="$($buildInfo.version)" `
        -p:FileVersion="$($buildInfo.version).$($buildInfo.build)" `
        -p:InformationalVersion="$($buildInfo.version)+$($buildInfo.build).$($buildInfo.commit)"
    if ($LASTEXITCODE) { throw 'dotnet publish failed.' }
    $exe = Join-Path $OutputDir "$name.exe"
    Copy-Item (Join-Path $publishDir "$name.exe") $exe -Force
    Write-Host "Built $exe ($('{0:N1} MB' -f ((Get-Item $exe).Length / 1MB)), version $version)" -ForegroundColor Green
}

Remove-Item $stage -Recurse -Force
Write-Host "Built $(Join-Path $OutputDir 'build.json'): version $version" -ForegroundColor Green
