function Invoke-CcPlan {
    <#
    .SYNOPSIS
        Runs a plan against the target. DryRun (the default) goes through every write exactly as Apply
        would - payloads, reference rewriting, dependency order, the final link pass - and writes
        nothing; a record created earlier in the run gets a stand-in ID so the records that need it
        are checked against it instead of reported missing. Apply snapshots what it changes and
        records what it creates, so the run can be rolled back.
    .PARAMETER Mode
        DryRun (default) or Apply.
    .PARAMETER Approved
        Required to apply to an environment marked requireApproval (for example Prod).
    .EXAMPLE
        Invoke-CcPlan -Plan $plan -Environments $envs -Mode Apply -Approved -OutputDir ./out
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [pscustomobject] $Plan,
        [Parameter(Mandatory)] [object[]] $Environments,
        [ValidateSet('DryRun', 'Apply')] [string] $Mode = 'DryRun',
        [switch] $Approved,
        [string] $OutputDir = './out',
        [int] $ProvisioningTimeoutSeconds = 60,
        # Called as & $OnEvent <type> <data> while the run goes: 'start' (an operation or link is about
        # to be written; data = @{ phase; op }), 'item' (one outcome; data = the item), 'updated' (the
        # pre-run state of every record about to be changed; data = snapshot entries), 'created' (a
        # record the run created; data = its snapshot entry). Background runs use it for live progress
        # and a rollback snapshot that survives a crash mid-run.
        [scriptblock] $OnEvent,
        # Stop cleanly before the next write once this time has passed, and return with
        # incomplete = $true. A continuation compares again and plans the same selection: what was
        # written is then the same in both and drops out, so only the rest is done.
        [datetime] $Deadline = [datetime]::MaxValue
    )

    $target = $Environments | Where-Object Id -eq $Plan.target | Select-Object -First 1
    if (-not $target) { throw "Target '$($Plan.target)' is not connected." }
    if ($target.RequireApproval -and $Mode -eq 'Apply' -and -not $Approved) {
        throw "$($target.Name) requires approval. Confirm the change has been signed off, then apply again."
    }

    $ctx = $Plan._context
    $manifest = $ctx.Manifest
    $plans = $ctx.TablePlans
    # A copy: the dry run's stand-in IDs must not leak into a diff that is reused afterwards.
    $maps = @{
        SourceGuidToRef = $ctx.Maps.SourceGuidToRef
        TargetGuidToRef = $ctx.Maps.TargetGuidToRef
        TargetKeyToGuid = $ctx.Maps.TargetKeyToGuid.Clone()
        Labels          = $ctx.Maps.Labels
    }
    $isDry = $Mode -eq 'DryRun'

    if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir | Out-Null }
    $runId = "run_$([guid]::NewGuid().ToString('N').Substring(0, 12))"
    $started = (Get-Date).ToString('o')

    $snapshotPath = $null
    $snapshot = [ordered]@{ environment = $target.Id; taken = $started; runId = $runId; updated = [System.Collections.Generic.List[object]]::new(); created = [System.Collections.Generic.List[object]]::new() }
    $updateOps = @($Plan.operations | Where-Object { $_.status -eq 'ready' -and $_.op -eq 'update' })
    if (-not $isDry) {
        foreach ($o in $updateOps) {
            $tid = $maps.TargetKeyToGuid["$($o.table)|$($o.matchKey)"]
            $trec = if ($tid) { $ctx.Target.ById[$o.table][$tid] } else { $null }
            if ($trec) { $snapshot.updated.Add((New-CcSnapshotEntry -TargetRecord $trec -TablePlan $plans[$o.table] -TargetId $tid -TablePlans $plans)) | Out-Null }
        }
        if ($OnEvent) { & $OnEvent 'updated' @($snapshot.updated) }
        $snapshotPath = Join-Path $OutputDir "snapshot-$runId.json"
        $snapshot | ConvertTo-Json -Depth 40 | Set-Content -Path $snapshotPath -Encoding UTF8
    }

    $items = [System.Collections.Generic.List[object]]::new()
    $failedRefs = @{}
    $links = [System.Collections.Generic.List[object]]::new()

    function Add-Item($o, $outcome, $message, [int] $stage) {
        $item = [pscustomobject]@{
            seq = $o.seq; stage = $stage; table = $o.table; matchKey = $o.matchKey; tableLabel = $o.tableLabel
            displayName = $o.displayName; context = $o.context; op = $o.op; outcome = $outcome; message = $message
        }
        $items.Add($item) | Out-Null
        if ($OnEvent) { & $OnEvent 'item' $item }
    }
    $incomplete = $false
    $attempted = 0

    foreach ($o in @($Plan.operations | Where-Object status -eq 'blocked')) {
        Add-Item $o 'blocked' (($o.blockers | ForEach-Object message) -join ' ') $o.stage
        $failedRefs["$($o.table)|$($o.matchKey)"] = $o.displayName
    }

    $readyOps = @($Plan.operations | Where-Object status -eq 'ready' | Sort-Object stage, order, seq)
    foreach ($o in $readyOps) {
        $ref = "$($o.table)|$($o.matchKey)"
        $tplan = $plans[$o.table]
        # At least one write per call before the deadline counts, so a slice whose compare used up
        # its budget still makes progress instead of handing the same work on forever.
        if (-not $isDry -and $attempted -gt 0 -and (Get-Date) -gt $Deadline) { $incomplete = $true; break }
        $attempted++
        if ($OnEvent) { & $OnEvent 'start' @{ phase = 'writing'; op = $o } }

        if ($o.op -eq 'skip-existing') { Add-Item $o 'unchanged' 'Already in the target; this table is never changed after it is created.' $o.stage; continue }

        $waitsOn = @($o.dependencies | Where-Object { $_.state -in 'createdEarlier', 'linkedLater' -and $failedRefs.ContainsKey("$($_.table)|$($_.matchKey)") })
        if ($waitsOn) {
            Add-Item $o 'skipped' "Not written because $($waitsOn[0].label) could not be written." $o.stage
            $failedRefs[$ref] = $o.displayName
            continue
        }

        $srcId = Get-CcIdByKey -Env $ctx.Source -Table $o.table -Key $o.matchKey
        $src = if ($srcId) { $ctx.Source.ById[$o.table][$srcId] } else { $null }
        if (-not $src) { Add-Item $o 'failed' 'The source record could not be found any more. Compare again.' $o.stage; $failedRefs[$ref] = $o.displayName; continue }

        $writeOp = if ($o.op -eq 'create') { 'create' } else { 'update' }
        $built = Build-CcWritePayload -SourceRecord $src -TablePlan $tplan -Op $writeOp -Maps $maps -TablePlans $plans
        if ($built.Blocked) {
            Add-Item $o 'skipped' ($built.Problems -join ' ') $o.stage
            $failedRefs[$ref] = $o.displayName
            continue
        }
        $tgtId = if ($o.op -eq 'update') { $maps.TargetKeyToGuid[$ref] } else { $null }

        if ($isDry) {
            $id = if ($tgtId) { $tgtId } else { [guid]::NewGuid().ToString() }
            $maps.TargetKeyToGuid[$ref] = $id
            $verb = if ($o.op -eq 'create') { 'wouldCreate' } else { 'wouldUpdate' }
            $n = @($built.Payload.Keys).Count
            Add-Item $o $verb "$n setting$(if ($n -ne 1) { 's' }) $(if ($o.op -eq 'create') { 'set' } else { 'written' })$(if ($built.Deferred.Count) { "; $($built.Deferred.Count) link$(if ($built.Deferred.Count -ne 1) { 's' }) set at the end" })." $o.stage
            foreach ($d in $built.Deferred) { $links.Add([pscustomobject]@{ Op = $o; RecordId = $id; Lookup = $d.Lookup; Entity = $d.Entity; Key = $d.Key }) | Out-Null }
            continue
        }

        if (-not $PSCmdlet.ShouldProcess("$($o.tableLabel) '$($o.displayName)' in $($target.Name)", $o.op)) { continue }
        try {
            $id = Invoke-CcUpsert -Environment $target -EntitySet $tplan.EntitySet -PrimaryId $tplan.PrimaryId -Payload $built.Payload -TargetGuid $tgtId
            if (-not $id) { throw 'Dataverse did not return the new record.' }
            $maps.TargetKeyToGuid[$ref] = $id
            if ($o.op -eq 'create') {
                $createdEntry = [ordered]@{ table = $o.table; entitySet = $tplan.EntitySet; id = $id; label = $o.displayName; order = $o.order }
                $snapshot.created.Add($createdEntry) | Out-Null
                if ($OnEvent) { & $OnEvent 'created' $createdEntry }
            }
            $note = ''
            if ($tplan.Table.async -and $o.op -eq 'create') {
                if (-not (Wait-CcProvisioning -Environment $target -WorkstreamId $id -TimeoutSeconds $ProvisioningTimeoutSeconds)) {
                    $note = ' Provisioning was not confirmed in time; check the workstream in the target.'
                }
            }
            if ($tplan.Table.doubleWrite) {
                # The second write lands the ruleset's dependency mappings, against the record's real id.
                # It is an update, so it carries only what an update may set: a create's body
                # includes the unique name, which Dataverse does not accept on an update.
                Start-Sleep -Seconds 2
                $second = if ($writeOp -eq 'create') { (Build-CcWritePayload -SourceRecord $src -TablePlan $tplan -Op 'update' -Maps $maps -TablePlans $plans).Payload } else { $built.Payload }
                Invoke-CcUpsert -Environment $target -EntitySet $tplan.EntitySet -PrimaryId $tplan.PrimaryId -Payload $second -TargetGuid $id | Out-Null
            }
            $outcome = if ($o.op -eq 'create') { 'created' } else { 'updated' }
            Add-Item $o $outcome ("Done.$note").Trim() $o.stage
            foreach ($d in $built.Deferred) { $links.Add([pscustomobject]@{ Op = $o; RecordId = $id; Lookup = $d.Lookup; Entity = $d.Entity; Key = $d.Key }) | Out-Null }
        }
        catch {
            Add-Item $o 'failed' (Get-CcErrorMessage $_.Exception.Message) $o.stage
            $failedRefs[$ref] = $o.displayName
        }
    }

    # Final pass: lookups that pointed at a table written later (a workstream's default queue, a
    # queue's overflow ruleset) now have their target.
    # Links wait for a continuation when the run stopped early: the records they point at may not
    # exist yet, and the continuation queues them again from its own plan.
    if ($incomplete) { $links.Clear() }
    foreach ($l in $links) {
        if ($OnEvent) { & $OnEvent 'start' @{ phase = 'linking'; op = $l.Op } }
        $targetGuid = $maps.TargetKeyToGuid["$($l.Entity)|$($l.Key)"]
        $what = "$($l.Lookup.Label) of $(Get-CcItemLabel $plans[$l.Op.table].Table) '$($l.Op.displayName)'"
        $linkOp = [pscustomobject]@{ seq = $l.Op.seq; table = $l.Op.table; matchKey = $l.Op.matchKey; tableLabel = $l.Op.tableLabel; displayName = $l.Op.displayName; context = $l.Op.context; op = 'link' }
        $refLabel = Get-CcRefLabel $maps $l.Entity $l.Key $plans
        if (-not $targetGuid) {
            Add-Item $linkOp 'skipped' "$what not set: $refLabel is not in the target." 99
            continue
        }
        if ($isDry) { Add-Item $linkOp 'wouldLink' "$what will point at $refLabel." 99; continue }
        try {
            $body = @{ "$($l.Lookup.Nav)@odata.bind" = "/$($plans[$l.Entity].EntitySet)($targetGuid)" }
            Invoke-CcWebApi -Environment $target -Method Patch -Path "$($plans[$l.Op.table].EntitySet)($($l.RecordId))" -Body $body -Prefer $null | Out-Null
            Add-Item $linkOp 'linked' "$what now points at $refLabel." 99
        }
        catch {
            Add-Item $linkOp 'failed' "$what could not be set: $(Get-CcErrorMessage $_.Exception.Message)" 99
        }
    }

    if (-not $isDry -and $snapshotPath) {
        $snapshot | ConvertTo-Json -Depth 40 | Set-Content -Path $snapshotPath -Encoding UTF8
    }

    $okOutcomes = 'created', 'updated', 'linked', 'unchanged', 'wouldCreate', 'wouldUpdate', 'wouldLink'
    $bad = @($items | Where-Object { $_.outcome -notin $okOutcomes })
    $good = @($items | Where-Object { $_.outcome -in $okOutcomes -and $_.outcome -ne 'unchanged' })
    $state = if ($bad.Count -eq 0) { 'Succeeded' } elseif ($good.Count -eq 0) { 'Failed' } else { 'PartiallyFailed' }

    $stageResults = [ordered]@{}
    foreach ($stage in @($items.stage | Sort-Object -Unique)) {
        $si = @($items | Where-Object stage -eq $stage)
        $sBad = @($si | Where-Object { $_.outcome -notin $okOutcomes })
        $sGood = @($si | Where-Object { $_.outcome -in $okOutcomes -and $_.outcome -ne 'unchanged' })
        $stageResults["stage$stage"] = [pscustomobject]@{
            label    = Get-CcStageLabel $manifest $stage
            state    = if ($sBad.Count -eq 0) { 'Succeeded' } elseif ($sGood.Count -eq 0) { 'Failed' } else { 'PartiallyFailed' }
            written  = $sGood.Count
            warnings = @($sBad | ForEach-Object { "$($_.tableLabel) '$($_.displayName)': $($_.message)" })
            items    = $si
        }
    }

    $summary = [pscustomobject]@{
        created  = @($items | Where-Object { $_.outcome -in 'created', 'wouldCreate' }).Count
        updated  = @($items | Where-Object { $_.outcome -in 'updated', 'wouldUpdate' }).Count
        linked   = @($items | Where-Object { $_.outcome -in 'linked', 'wouldLink' }).Count
        skipped  = @($items | Where-Object { $_.outcome -eq 'skipped' }).Count
        blocked  = @($items | Where-Object { $_.outcome -eq 'blocked' }).Count
        failed   = @($items | Where-Object { $_.outcome -eq 'failed' }).Count
    }

    $run = [pscustomobject]@{
        runId      = $runId
        mode       = $Mode
        source     = $Plan.source
        target     = $target.Id
        state      = $state
        snapshot   = $snapshotPath
        startedAt  = $started
        finishedAt = (Get-Date).ToString('o')
        summary    = $summary
        incomplete = $incomplete
        stages     = $stageResults
        problems   = @($bad | ForEach-Object { "$($_.tableLabel) '$($_.displayName)': $($_.message)" })
    }
    $run | ConvertTo-Json -Depth 30 | Set-Content -Path (Join-Path $OutputDir "run-$runId.json") -Encoding UTF8

    $verb = if ($isDry) { 'Dry run' } else { 'Run' }
    Write-Host "$verb $runId : $state. $($summary.created) new, $($summary.updated) changed, $($summary.linked) linked, $($summary.skipped + $summary.blocked) not moved, $($summary.failed) failed." -ForegroundColor Cyan
    foreach ($p in $run.problems) { Write-Host "  - $p" -ForegroundColor Yellow }
    return $run
}
