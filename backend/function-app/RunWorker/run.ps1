param($QueueItem, $TriggerMetadata)

# Does the work behind Apply and Rollback, one slice at a time. A slice stops cleanly before the
# 10-minute Functions limit and queues the next one; the next slice compares again, so it writes
# only what is still missing. maxDequeueCount is 1 (host.json): a crashed slice is never retried
# blindly - its run shows as Interrupted and the person decides whether to continue.
$msg = if ($QueueItem -is [string]) { $QueueItem | ConvertFrom-Json } else { $QueueItem }
$runId = [string]$msg.runId
$kind = [string]$msg.kind
$runName = "run-$runId.json"
$snapName = "snapshot-$runId.json"

$load = { Get-CcBlobJson $runName }.GetNewClosure()
$save = { param($r) Save-CcBlobJson $runName $r }.GetNewClosure()

try {
    $run = Get-CcBlobJson $runName
    $envs = Get-CcConnected @($run.source, $run.target)

    if ($kind -eq 'rollback') {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) $snapName
        Get-CcBlobFile $snapName $tmp | Out-Null
        Invoke-CcRollbackJob -Environments $envs -LoadRun $load -SaveRun $save -SnapshotPath $tmp
        Remove-Item $tmp -ErrorAction SilentlyContinue
        return
    }

    $loadSnap = { try { Get-CcBlobJson $snapName } catch { $null } }.GetNewClosure()
    $saveSnap = { param($s) Save-CcBlobJson $snapName $s }.GetNewClosure()
    $work = Join-Path ([System.IO.Path]::GetTempPath()) "ccalm-$runId"
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    $loadReads = { param($diffId) Get-CcReads $diffId }
    $result = Invoke-CcRunJob -Environments $envs -LoadRun $load -SaveRun $save -LoadSnapshot $loadSnap -SaveSnapshot $saveSnap `
        -LoadReads $loadReads -WorkDir $work -TimeBudgetSeconds 420
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
    if ($result.Continue) {
        Push-OutputBinding -Name RunQueue -Value (@{ runId = $runId; kind = 'apply' } | ConvertTo-Json -Compress)
    }
}
catch {
    # Never rethrow: a retry could repeat writes. Record the failure on the run instead.
    try {
        $run = ConvertTo-CcRunHashtable (Get-CcBlobJson $runName)
        $run.state = 'Failed'
        $run.phase = 'done'
        $run.message = Get-CcErrorText $_
        $run.updatedAt = (Get-Date).ToString('o')
        Save-CcBlobJson $runName $run
    }
    catch { Write-Error "Run $runId failed and could not be updated: $($_.Exception.Message)" }
}
