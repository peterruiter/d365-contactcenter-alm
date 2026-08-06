using namespace System.Net
param($Request, $TriggerMetadata)

try {
    $id = $Request.Params.id
    if (-not $id) { Push-CcError 400 'bad_request' 'Run id is required.'; return }

    try {
        $run = Get-CcBlobJson "run-$id.json"
    }
    catch {
        Push-CcError 404 'not_found' "Run $id not found."; return
    }

    if (-not $run.snapshotId) {
        Push-CcError 400 'no_snapshot' 'This run has no snapshot. A dry run cannot be rolled back.'; return
    }

    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "snapshot-$id.json"
    Get-CcBlobFile "snapshot-$id.json" $tmp | Out-Null

    $envs = Get-CcConnected
    $result = Restore-CcRun -SnapshotPath $tmp -Environments $envs -Confirm:$false
    Remove-Item $tmp -ErrorAction SilentlyContinue

    $run.state = 'RolledBack'
    Save-CcBlobJson "run-$id.json" $run

    Push-CcJson 200 @{
        runId   = $id
        state   = 'RolledBack'
        cleanup = @{ restored = $result.restored; unresolved = @($result.unresolved) }
        stages  = @($run.stages)
        mode    = $run.mode
        target  = $run.target
        snapshotId = $run.snapshotId
        problems = @($run.problems)
    }
}
catch {
    Push-CcError 500 'rollback_failed' (Get-CcErrorText $_)
}
