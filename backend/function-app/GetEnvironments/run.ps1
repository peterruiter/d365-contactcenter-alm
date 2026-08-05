using namespace System.Net
param($Request, $TriggerMetadata)

try {
    if (-not $env:CCALM_ENVIRONMENTS) { Push-CcError 500 'config' 'CCALM_ENVIRONMENTS is not set.'; return }
    $cfg = $env:CCALM_ENVIRONMENTS | ConvertFrom-Json
    $envs = @($cfg.environments | ForEach-Object {
        [ordered]@{
            id              = $_.id
            name            = $_.name
            url             = $_.url
            role            = if ($_.role) { $_.role } else { 'any' }
            requireApproval = [bool]$_.requireApproval
        }
    })
    Push-CcJson 200 $envs
}
catch {
    Push-CcError 500 'environments_failed' $_.Exception.Message
}
