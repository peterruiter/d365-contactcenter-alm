<#
.SYNOPSIS
    Tests and builds the XrmToolBox tool: out/ContactCenterALM.XrmToolBox.<version>.nupkg for the
    XrmToolBox Tool Library, and out/ContactCenterALM-XrmToolBox.zip to install by hand.
.EXAMPLE
    ./xrmtoolbox/build.ps1
#>
#Requires -Version 7.2
param([string] $ReleaseNotes = 'See https://github.com/peterruiter/d365-contactcenter-alm/blob/master/CHANGELOG.md')

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$out = Join-Path (Split-Path $here -Parent) 'out'
New-Item -ItemType Directory -Path $out -Force | Out-Null

dotnet test (Join-Path $here 'tests/CcAlm.Core.Tests/CcAlm.Core.Tests.csproj') -nologo -v q
if ($LASTEXITCODE) { throw 'Tests failed.' }

# The version: the project version plus the repo's commit count, like the local runner's build number.
$build = [int](git -C $here rev-list --count HEAD)
$version = "0.1.$build"
dotnet build (Join-Path $here 'src/CcAlm.XrmToolBox/CcAlm.XrmToolBox.csproj') -c Release -nologo -v q -p:Version=$version
if ($LASTEXITCODE) { throw 'Build failed.' }

# dotnet pack needs a project; the nuspec decides the contents. Version and release notes are written
# into a copy of it (MSBuild cannot pass two nuspec properties that NuGet then splits).
$spec = Get-Content (Join-Path $here 'ContactCenterALM.XrmToolBox.nuspec') -Raw
$spec = $spec.Replace('$version$', $version).Replace('$releaseNotes$', [Security.SecurityElement]::Escape($ReleaseNotes))
$specPath = Join-Path $here 'obj/ContactCenterALM.XrmToolBox.nuspec'
New-Item -ItemType Directory -Path (Split-Path $specPath) -Force | Out-Null
Set-Content -Path $specPath -Value $spec -Encoding utf8NoBOM
# NU5048: the package deliberately carries both icon and iconUrl; see the nuspec.
dotnet pack (Join-Path $here 'src/CcAlm.XrmToolBox/CcAlm.XrmToolBox.csproj') -c Release --no-build -nologo -v q -o $out "-p:NuspecFile=$specPath" "-p:NuspecBasePath=$here" -p:NoWarn=NU5048
if ($LASTEXITCODE) { throw 'Pack failed.' }

$zip = Join-Path $out 'ContactCenterALM-XrmToolBox.zip'
if (Test-Path $zip) { Remove-Item $zip -Force }
$bin = Join-Path $here 'src/CcAlm.XrmToolBox/bin/Release/net48'
Compress-Archive -Path (Join-Path $bin 'CcAlm.XrmToolBox.dll'), (Join-Path $bin 'CcAlm.Core.dll') -DestinationPath $zip
Write-Host "Built $out\ContactCenterALM.XrmToolBox.$version.nupkg and $zip (version $version)." -ForegroundColor Green
