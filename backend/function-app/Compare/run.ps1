using namespace System.Net
param($Request, $TriggerMetadata)

try {
    $body = Read-CcBody $Request
    if (-not $body.sourceEnvId -or -not $body.targetEnvId) {
        Push-CcError 400 'bad_request' 'sourceEnvId and targetEnvId are required.'; return
    }

    $envs = Get-CcConnected @($body.sourceEnvId, $body.targetEnvId)
    $tables = if ($body.tables) { @($body.tables) } else { $null }

    $diff = Compare-CcConfig -Environments $envs -SourceId $body.sourceEnvId -TargetId $body.targetEnvId -Tables $tables
    Push-CcJson 200 (ConvertTo-CcDiffContract $diff)
}
catch {
    Push-CcError 500 'compare_failed' (Get-CcErrorText $_)
}
