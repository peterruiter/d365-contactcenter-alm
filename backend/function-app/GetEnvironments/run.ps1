using namespace System.Net
param($Request, $TriggerMetadata)

try {
    $cfg = (Get-CcRegistryJson) | ConvertFrom-Json
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
    Push-CcError 500 'environments_failed' (Get-CcErrorText $_)
}
