<#
.SYNOPSIS
    Compare, build a plan, dry-run, then apply. Dry-run is the default. Add -Apply to write.
.EXAMPLE
    ./backend/cli/migrate.ps1 -Config ./environments.json -Source acc -Target prod            # dry-run
.EXAMPLE
    ./backend/cli/migrate.ps1 -Config ./environments.json -Source acc -Target prod -Apply -Approved
.NOTES
    Prod (or any environment with requireApproval) needs -Approved to apply.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Config,
    [Parameter(Mandatory)] [string] $Source,
    [Parameter(Mandatory)] [string] $Target,
    [string[]] $Tables,
    [switch] $Apply,
    [switch] $Approved,
    [string] $OutputDir = './out'
)

Import-Module "$PSScriptRoot/../function-app/Modules/CcAlm/CcAlm.psd1" -Force

$envs = Connect-CcEnvironment -ConfigPath $Config
$diff = Compare-CcConfig -Environments $envs -SourceId $Source -TargetId $Target -Tables $Tables -OutputDir $OutputDir
$plan = New-CcPlan -Diff $diff

if ($plan.operations.Count -eq 0) {
    Write-Host 'Nothing to move. Target already matches source for the selected tables.' -ForegroundColor Green
    return
}

$mode = if ($Apply) { 'Apply' } else { 'DryRun' }
Invoke-CcPlan -Plan $plan -Environments $envs -Mode $mode -Approved:$Approved -OutputDir $OutputDir
