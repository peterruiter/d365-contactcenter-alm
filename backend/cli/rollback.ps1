<#
.SYNOPSIS
    Roll back a run from its snapshot file.
.EXAMPLE
    ./backend/cli/rollback.ps1 -Config ./environments.json -Snapshot ./out/snapshot-run_abc123.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Config,
    [Parameter(Mandatory)] [string] $Snapshot
)

Import-Module "$PSScriptRoot/../function-app/Modules/CcAlm/CcAlm.psd1" -Force

$envs = Connect-CcEnvironment -ConfigPath $Config
Restore-CcRun -SnapshotPath $Snapshot -Environments $envs -Confirm:$false
