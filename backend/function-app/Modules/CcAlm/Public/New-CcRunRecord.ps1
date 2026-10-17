function New-CcRunRecord {
    <#
    .SYNOPSIS
        The stored state of a background run, in the shape the app reads (GetRun returns it as is),
        plus the request it was started with so it can be run, continued or resumed by a worker.
    #>
    param(
        [Parameter(Mandatory)] [string] $SourceId,
        [Parameter(Mandatory)] [string] $TargetId,
        [Parameter(Mandatory)] [ValidateSet('apply', 'dryRun')] [string] $Mode,
        [object[]] $Selection,
        [bool] $Approved,
        # The compare the run was planned from; with its reads kept, the run need not read again.
        [string] $DiffId
    )
    $now = (Get-Date).ToString('o')
    [ordered]@{
        runId      = "run_$([guid]::NewGuid().ToString('N').Substring(0, 12))"
        mode       = $Mode
        source     = $SourceId
        target     = $TargetId
        state      = 'Queued'
        phase      = 'queued'
        message    = $null
        progress   = [ordered]@{ done = 0; total = 0; current = $null }
        startedAt  = $now
        updatedAt  = $now
        finishedAt = $null
        summary    = [ordered]@{ created = 0; updated = 0; linked = 0; skipped = 0; blocked = 0; failed = 0 }
        stages     = @()
        items      = @()
        problems   = @()
        snapshotId = $null
        executions = 0
        request    = [ordered]@{ selection = @($Selection | ForEach-Object { [ordered]@{ table = $_.table; matchKey = $_.matchKey } }); approved = $Approved; diffId = $(if ($DiffId) { $DiffId } else { $null }) }
    }
}
