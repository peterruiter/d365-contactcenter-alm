using namespace System.Net
param($Request, $TriggerMetadata)

# Starts rolling back an applied run in the background; the app polls GetRun until it finishes.
try {
    $id = $Request.Params.id
    if (-not $id) { Push-CcError 400 'bad_request' 'Run id is required.'; return }
    try { $run = ConvertTo-CcRunHashtable (Get-CcBlobJson "run-$id.json") }
    catch { Push-CcError 404 'not_found' "Run $id not found."; return }

    if (-not $run.snapshotId) { Push-CcError 400 'no_snapshot' 'This run has no snapshot. A dry run cannot be rolled back.'; return }
    if ($run.state -in 'Queued', 'Running', 'RollingBack' -and -not (Test-CcRunStale $run)) {
        Push-CcError 409 'busy' 'This run is still in progress. Roll it back once it has finished.'; return
    }

    $run.state = 'RollingBack'
    $run.phase = 'rollingBack'
    $run.progress.current = 'Waiting to start'
    $run.updatedAt = (Get-Date).ToString('o')
    Save-CcBlobJson "run-$id.json" $run
    Push-OutputBinding -Name RunQueue -Value (@{ runId = $id; kind = 'rollback' } | ConvertTo-Json -Compress)
    Push-CcJson 200 $run
}
catch {
    Push-CcError 500 'rollback_failed' (Get-CcErrorText $_)
}
