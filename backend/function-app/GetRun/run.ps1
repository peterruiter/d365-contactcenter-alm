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
    Push-CcJson 200 $run
}
catch {
    Push-CcError 500 'run_failed' (Get-CcErrorText $_)
}
