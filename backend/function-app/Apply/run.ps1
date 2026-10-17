using namespace System.Net
param($Request, $TriggerMetadata)

# Starts a dry run or an apply in the background and returns at once with the run record; the app
# polls GetRun for progress. A run can outlast the connector's request timeout and the Function's
# HTTP limit, so the work happens in RunWorker, a queue-triggered function.
try {
    $body = Read-CcBody $Request
    if (-not $body.sourceEnvId -or -not $body.targetEnvId) {
        Push-CcError 400 'bad_request' 'sourceEnvId and targetEnvId are required.'; return
    }
    $mode = if ($body.mode -eq 'apply') { 'apply' } else { 'dryRun' }
    $approved = [bool]$body.approved

    $cfg = (Get-CcRegistryJson) | ConvertFrom-Json
    $target = $cfg.environments | Where-Object id -eq $body.targetEnvId | Select-Object -First 1
    if (-not $target) { Push-CcError 400 'bad_request' "Unknown target '$($body.targetEnvId)'."; return }
    if ($mode -eq 'apply' -and $target.requireApproval -and -not $approved) {
        Push-CcError 400 'approval_required' "$($target.name) requires approval. Confirm the change has been signed off, then apply again."; return
    }

    $selection = @($body.selection | ForEach-Object { @{ table = $_.table; matchKey = $_.matchKey } })
    $run = New-CcRunRecord -SourceId $body.sourceEnvId -TargetId $body.targetEnvId -Mode $mode -Selection $selection -Approved $approved -DiffId ([string]$body.diffId)
    Save-CcBlobJson "run-$($run.runId).json" $run
    Push-OutputBinding -Name RunQueue -Value (@{ runId = $run.runId; kind = 'apply' } | ConvertTo-Json -Compress)
    Push-CcJson 200 $run
}
catch {
    Push-CcError 500 'apply_failed' (Get-CcErrorText $_)
}
