function Invoke-CcRollbackJob {
    <#
    .SYNOPSIS
        Rolls back a stored run in the background: restores what it changed, deletes what it created,
        and records the outcome on the run.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object[]] $Environments,
        [Parameter(Mandatory)] [scriptblock] $LoadRun,
        [Parameter(Mandatory)] [scriptblock] $SaveRun,
        [Parameter(Mandatory)] [string] $SnapshotPath
    )
    $run = ConvertTo-CcHashtable (& $LoadRun)
    try {
        $run.state = 'RollingBack'
        $run.phase = 'rollingBack'
        $run.progress.current = 'Restoring changed records and deleting created ones'
        $run.updatedAt = (Get-Date).ToString('o')
        & $SaveRun $run
        $result = Restore-CcRun -SnapshotPath $SnapshotPath -Environments $Environments -Confirm:$false 6>$null
        $run.state = 'RolledBack'
        $run.cleanup = [ordered]@{ restored = $result.restored; deleted = $result.deleted; unlinked = $result.unlinked; unresolved = @($result.unresolved) }
    }
    catch {
        $run.state = 'PartiallyFailed'
        $run.message = "Rollback stopped: $(Get-CcErrorMessage $_.Exception.Message)"
    }
    $run.phase = 'done'
    $run.progress.current = $null
    $run.updatedAt = (Get-Date).ToString('o')
    & $SaveRun $run
}
