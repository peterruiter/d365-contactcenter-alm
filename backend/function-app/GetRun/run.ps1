using namespace System.Net
param($Request, $TriggerMetadata)

try {
    $id = $Request.Params.id
    if (-not $id) { Push-CcError 400 'bad_request' 'Run id is required.'; return }
    try { $run = Get-CcBlobJson "run-$id.json" }
    catch { Push-CcError 404 'not_found' "Run $id not found."; return }

    # A run that says it is busy but has not saved for a while lost its worker (a restart, the
    # 10-minute limit). Say so, so the app can offer to continue it.
    if (Test-CcRunStale $run) {
        $run = ConvertTo-CcRunHashtable $run
        $run.state = 'Interrupted'
        $run.phase = 'done'
        $run.message = 'This run stopped before it finished. Continuing it compares again and writes only what is still missing.'
        Save-CcBlobJson "run-$id.json" $run
    }
    Push-CcJson 200 $run
}
catch {
    Push-CcError 500 'run_failed' (Get-CcErrorText $_)
}
