using namespace System.Net
param($Request, $TriggerMetadata)

try {
    $body = Read-CcBody $Request
    if (-not $body.sourceEnvId -or -not $body.targetEnvId) {
        Push-CcError 400 'bad_request' 'sourceEnvId and targetEnvId are required.'; return
    }

    $mode = if ($body.mode -eq 'apply') { 'Apply' } else { 'DryRun' }
    $approved = [bool]$body.approved

    $envs = Get-CcConnected
    $diff = Compare-CcConfig -Environments $envs -SourceId $body.sourceEnvId -TargetId $body.targetEnvId

    $selection = if ($body.selection) {
        @($body.selection | ForEach-Object { @{ table = $_.table; matchKey = $_.matchKey } })
    } else { $null }

    $plan = New-CcPlan -Diff $diff -Selection $selection
    if ($plan.operations.Count -eq 0) {
        Push-CcJson 200 @{ runId = 'run_noop'; mode = $body.mode; target = $body.targetEnvId; state = 'Succeeded'; snapshotId = $null; stages = @(); problems = @() }
        return
    }

    $outDir = Join-Path ([System.IO.Path]::GetTempPath()) "ccalm-$([guid]::NewGuid().ToString('N').Substring(0,8))"
    New-Item -ItemType Directory -Path $outDir | Out-Null

    $run = Invoke-CcPlan -Plan $plan -Environments $envs -Mode $mode -Approved:$approved -OutputDir $outDir

    $snapshotId = $null
    if ($mode -eq 'Apply' -and $run.snapshot -and (Test-Path $run.snapshot)) {
        $snapshotId = $run.runId
        $container = Confirm-CcRunsContainer
        Set-AzStorageBlobContent -File $run.snapshot -Container $container -Blob "snapshot-$($run.runId).json" -Context (Get-CcBlobContext) -Force | Out-Null
    }

    $contract = ConvertTo-CcRunContract $run $snapshotId
    Save-CcBlobJson "run-$($run.runId).json" $contract
    Remove-Item $outDir -Recurse -Force -ErrorAction SilentlyContinue

    Push-CcJson 200 $contract
}
catch {
    Push-CcError 500 'apply_failed' (Get-CcErrorText $_)
}
