<#
.SYNOPSIS
    Compare Contact Center config between two environments and write a diff report.
.EXAMPLE
    ./scripts/compare.ps1 -Config ./environments.json -Source acc -Target prod
.EXAMPLE
    $env:CCALM_CLIENT_SECRET = '...'; ./scripts/compare.ps1 -Config ./environments.json -Source dev -Target test -Tables msdyn_liveworkstream,queue
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Config,
    [Parameter(Mandatory)] [string] $Source,
    [Parameter(Mandatory)] [string] $Target,
    [string[]] $Tables,
    [string] $OutputDir = './out'
)

Import-Module "$PSScriptRoot/../src/CcAlm/CcAlm.psd1" -Force

$envs = Connect-CcEnvironment -ConfigPath $Config
$null = Compare-CcConfig -Environments $envs -SourceId $Source -TargetId $Target -Tables $Tables -OutputDir $OutputDir
