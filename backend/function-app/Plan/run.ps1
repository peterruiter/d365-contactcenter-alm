using namespace System.Net
param($Request, $TriggerMetadata)

try {
    $body = Read-CcBody $Request
    if (-not $body.sourceEnvId -or -not $body.targetEnvId) {
        Push-CcError 400 'bad_request' 'sourceEnvId and targetEnvId are required.'; return
    }

    $envs = Get-CcConnected
    $diff = Compare-CcConfig -Environments $envs -SourceId $body.sourceEnvId -TargetId $body.targetEnvId

    $selection = if ($body.selection) {
        @($body.selection | ForEach-Object { @{ table = $_.table; matchKey = $_.matchKey } })
    } else { $null }

    $plan = New-CcPlan -Diff $diff -Selection $selection
    Push-CcJson 200 (ConvertTo-CcPlanContract $plan)
}
catch {
    Push-CcError 500 'plan_failed' (Get-CcErrorText $_)
}
