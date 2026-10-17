function Invoke-CcRunJob {
    <#
    .SYNOPSIS
        Runs (or continues) one stored background run: compares, plans exactly the requested
        selection, and writes, saving progress after every record. An apply then compares again and
        checks that every record it wrote now matches the source (run.verification). With a time
        budget it stops cleanly before running out and returns Continue = $true; the caller
        schedules another slice, which compares again so only what is still missing is written, or
        does only the check when that is all that is left.
    .PARAMETER LoadRun / SaveRun / LoadSnapshot / SaveSnapshot
        Storage, supplied by the host (files for the local runner, blobs for the Function).
        LoadSnapshot returns $null when there is none yet.
    .PARAMETER LoadReads
        Optional: & $LoadReads <diffId> returns the read cache of the compare the run was planned
        from (Import-CcReadCache), or $null. With it a dry run reads nothing from Dataverse, and an
        apply re-reads only the target's records, the one thing that must be current before writing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object[]] $Environments,
        [Parameter(Mandatory)] [scriptblock] $LoadRun,
        [Parameter(Mandatory)] [scriptblock] $SaveRun,
        [Parameter(Mandatory)] [scriptblock] $LoadSnapshot,
        [Parameter(Mandatory)] [scriptblock] $SaveSnapshot,
        [scriptblock] $LoadReads,
        [int] $TimeBudgetSeconds = 0,
        [string] $WorkDir = ([IO.Path]::GetTempPath()),
        [string] $ManifestPath = (Get-CcDefaultManifestPath)
    )

    $started = Get-Date
    $deadline = if ($TimeBudgetSeconds -gt 0) { $started.AddSeconds($TimeBudgetSeconds) } else { [datetime]::MaxValue }
    $run = ConvertTo-CcHashtable (& $LoadRun)
    $manifest = Get-CcManifest -Path $ManifestPath
    # Closures, not plain scriptblocks: the event handler runs inside Invoke-CcPlan, whose own
    # $items and $snapshot would otherwise shadow these through PowerShell's dynamic scoping.
    $state = @{ LastSave = [datetime]::MinValue }
    $save = {
        param([switch] $Force)
        if (-not $Force -and ((Get-Date) - $state.LastSave).TotalMilliseconds -lt 800) { return }
        $run.updatedAt = (Get-Date).ToString('o')
        & $SaveRun $run
        $state.LastSave = Get-Date
    }.GetNewClosure()

    # The compare this run was planned from, when the host kept its reads.
    $reads = $null
    if ($LoadReads -and $run.request.diffId) {
        try { $reads = & $LoadReads ([string]$run.request.diffId) } catch { $reads = $null }
    }
    $readArgs = @{}
    if ($reads) { $readArgs = @{ ReadCache = $reads; FreshRecords = @(if ($run.mode -eq 'apply') { $run.target }) } }

    try {
        $run.state = 'Running'
        $run.executions = [int]$run.executions + 1

        # Everything is written; an earlier slice left only the check.
        if ($run.verifyPending) {
            Invoke-CcRunVerification -Run $run -Environments $Environments -ManifestPath $ManifestPath -Save $save -ReadArgs $readArgs
            $run.verifyPending = $false
            Complete-CcRun -Run $run
            & $save -Force
            return [pscustomobject]@{ Continue = $false; RunId = $run.runId }
        }

        $run.phase = 'comparing'
        $run.progress.current = if (-not $reads) { 'Reading both environments' } elseif ($run.mode -eq 'apply') { "Reading the target again before writing" } else { 'Using what the compare read' }
        & $save -Force

        $sel = @($run.request.selection | ForEach-Object { @{ table = $_.table; matchKey = $_.matchKey } })
        $compareStarted = Get-Date
        $diff = Compare-CcConfig -Environments $Environments -SourceId $run.source -TargetId $run.target -ManifestPath $ManifestPath @readArgs 6>$null
        $compareSeconds = ((Get-Date) - $compareStarted).TotalSeconds
        # What was only in the target before anything was written, so the check afterwards can
        # tell what Dataverse added during the run. Taken once, by the first slice.
        if ($run.mode -eq 'apply' -and $null -eq $run.extraBefore) { $run.extraBefore = @(Get-CcExtraRefs $diff) }

        $run.phase = 'planning'
        $run.progress.current = 'Checking the plan'
        & $save -Force
        $plan = New-CcPlan -Diff $diff -Selection $sel -IncludeDependencies $false 6>$null

        # Items from earlier slices stay; this slice's outcomes replace or add to them.
        $items = [System.Collections.Generic.List[object]]::new()
        foreach ($i in @($run.items)) { if ($i) { $items.Add($i) | Out-Null } }
        $keyOf = { param($i) if ($i.op -eq 'link') { "link|$($i.table)|$($i.displayName)|$($i.message)" } else { "$($i.table)|$($i.context)|$($i.displayName)" } }.GetNewClosure()
        $previous = @{}
        foreach ($i in $items) { $previous[(& $keyOf $i)] = $i }

        $remaining = @($plan.operations).Count + [int]$plan.summary.links
        $run.progress.done = $items.Count
        $run.progress.total = $items.Count + $remaining
        $run.phase = 'writing'
        & $save -Force

        $snapshot = $null
        if ($run.mode -eq 'apply') {
            $snapshot = & $LoadSnapshot
            if (-not $snapshot) { $snapshot = [ordered]@{ environment = $run.target; runId = $run.runId; taken = (Get-Date).ToString('o'); updated = @(); created = @(); associated = @() } }
            else { $snapshot = ConvertTo-CcHashtable $snapshot }
            $run.snapshotId = $run.runId
        }

        $onEvent = {
            param($type, $data)
            switch ($type) {
                'start' {
                    $o = $data.op
                    $what = if ($o.context) { "$($o.context) › $($o.displayName)" } else { $o.displayName }
                    $run.progress.current = if ($data.phase -eq 'linking') { "Linking $what" } else { "$($o.tableLabel): $what" }
                    $run.phase = $data.phase
                    & $save
                }
                'item' {
                    $k = & $keyOf $data
                    $earlier = $previous[$k]
                    # A record created in an earlier slice and updated now (to set a link) stays "created".
                    if ($earlier -and $earlier.outcome -eq 'created' -and $data.outcome -eq 'updated') { return }
                    if ($earlier) { [void]$items.Remove($earlier) }
                    $items.Add($data) | Out-Null
                    $previous[$k] = $data
                    $run.items = @($items)
                    $run.progress.done = [Math]::Min($run.progress.total, $run.progress.done + 1)
                    & $save
                }
                'updated' {
                    $ids = @($snapshot.updated | ForEach-Object { $_.id })
                    $snapshot.updated = @($snapshot.updated) + @($data | Where-Object { $ids -notcontains $_.id })
                    & $SaveSnapshot $snapshot
                }
                'created' {
                    $snapshot.created = @($snapshot.created) + @($data)
                    & $SaveSnapshot $snapshot
                }
                'associated' {
                    $snapshot.associated = @($snapshot.associated | Where-Object { $_ }) + @($data)
                    & $SaveSnapshot $snapshot
                }
            }
        }.GetNewClosure()

        $mode = if ($run.mode -eq 'apply') { 'Apply' } else { 'DryRun' }
        $result = Invoke-CcPlan -Plan $plan -Environments $Environments -Mode $mode -Approved:([bool]$run.request.approved) `
            -OutputDir $WorkDir -OnEvent $onEvent -Deadline $deadline -Confirm:$false 6>$null

        $run.items = @($items)
        Update-CcRunTotals -Run $run -Manifest $manifest
        if ($result.incomplete) {
            $run.phase = 'continuing'
            $run.progress.current = 'Continuing in a moment'
            & $save -Force
            return [pscustomobject]@{ Continue = $true; RunId = $run.runId }
        }

        $wrote = @($run.items | Where-Object { $_ -and $_.outcome -in 'created', 'updated', 'linked' }).Count -gt 0
        if ($run.mode -eq 'apply' -and $wrote) {
            # The check is a full compare; when this slice has no room left for one, the next does it.
            $left = ($deadline - (Get-Date)).TotalSeconds
            if ($TimeBudgetSeconds -gt 0 -and $left -lt ($compareSeconds * 1.5 + 15)) {
                $run.verifyPending = $true
                $run.phase = 'continuing'
                $run.progress.current = 'Checking the result in a moment'
                & $save -Force
                return [pscustomobject]@{ Continue = $true; RunId = $run.runId }
            }
            Invoke-CcRunVerification -Run $run -Environments $Environments -ManifestPath $ManifestPath -Save $save -ReadArgs $readArgs
        }
        Complete-CcRun -Run $run
        & $save -Force
        return [pscustomobject]@{ Continue = $false; RunId = $run.runId }
    }
    catch {
        $run.state = 'Failed'
        $run.phase = 'done'
        $run.message = Get-CcErrorMessage $_.Exception.Message
        $run.progress.current = $null
        $run.finishedAt = (Get-Date).ToString('o')
        if ($run.items) { Update-CcRunTotals -Run $run -Manifest $manifest }
        & $save -Force
        return [pscustomobject]@{ Continue = $false; RunId = $run.runId }
    }
}
