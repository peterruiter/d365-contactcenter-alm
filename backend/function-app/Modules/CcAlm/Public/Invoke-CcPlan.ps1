function Invoke-CcPlan {
    <#
    .SYNOPSIS
        Runs a plan against the target environment. Dry-run by default. Snapshots the target before apply
        so a failed run can be rolled back.
    .PARAMETER Mode
        DryRun (default) reports what would happen and writes nothing. Apply executes.
    .PARAMETER Approved
        Required when the target environment has requireApproval set (for example Prod).
    .EXAMPLE
        Invoke-CcPlan -Plan $plan -Environments $envs -Mode Apply -Approved -OutputDir ./out
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [pscustomobject] $Plan,
        [Parameter(Mandatory)] [object[]] $Environments,
        [ValidateSet('DryRun','Apply')] [string] $Mode = 'DryRun',
        [switch] $Approved,
        [string] $OutputDir = './out',
        [int] $ProvisioningTimeoutSeconds = 60
    )

    $target = $Environments | Where-Object Id -eq $Plan.target | Select-Object -First 1
    if (-not $target) { throw "Target '$($Plan.target)' not connected." }
    if ($target.RequireApproval -and $Mode -eq 'Apply' -and -not $Approved) {
        throw "Target '$($target.Name)' requires approval. Re-run with -Approved once the change is signed off."
    }

    $ctx      = $Plan._context
    $manifest = $ctx.Manifest
    $maps     = $ctx.Maps
    $tableByLogical = @{}
    foreach ($t in $manifest.tables) { $tableByLogical[$t.logicalName] = $t }

    # Build comparable-key maps for source (payload source) and target (update vs create decision).
    $sourceByKey = @{}
    $targetByKey = @{}
    foreach ($logical in ($Plan.operations.table | Select-Object -Unique)) {
        $tbl = $tableByLogical[$logical]
        $sMap = @{}
        foreach ($r in $ctx.SourceRecordsByTable[$logical]) {
            $sMap[(Get-CcComparableKey -Record $r -Table $tbl -EnvIndexes $ctx.SourceIndexes)] = $r
        }
        $tMap = @{}
        foreach ($r in $ctx.TargetRecordsByTable[$logical]) {
            $guid = Get-CcRecordId -Record $r -Table $tbl
            $tMap[(Get-CcComparableKey -Record $r -Table $tbl -EnvIndexes $ctx.TargetIndexes)] = $guid
        }
        $sourceByKey[$logical] = $sMap
        $targetByKey[$logical] = $tMap
    }

    if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir | Out-Null }
    $runId = "run_$([guid]::NewGuid().ToString('N').Substring(0,12))"

    $snapshotPath = $null
    if ($Mode -eq 'Apply') {
        $snapshotPath = Join-Path $OutputDir "snapshot-$runId.json"
        Save-CcSnapshot -Environment $target -Operations $Plan.operations `
            -TargetIndexes $ctx.TargetIndexes -Path $snapshotPath | Out-Null
        Write-Host "Snapshot: $snapshotPath" -ForegroundColor DarkGray
    }

    $problems = [System.Collections.Generic.List[string]]::new()
    $stageResults = [ordered]@{}
    $state = 'Succeeded'

    $stages = $Plan.operations.stage | Sort-Object -Unique
    foreach ($stage in $stages) {
        $stageOps = $Plan.operations | Where-Object stage -eq $stage | Sort-Object order, seq
        $written = 0
        $warnings = [System.Collections.Generic.List[string]]::new()

        foreach ($op in $stageOps) {
            $tbl = $tableByLogical[$op.table]
            $src = $sourceByKey[$op.table][$op.matchKey]
            if (-not $src) { $warnings.Add("No source record for $($op.table) '$($op.matchKey)'.") | Out-Null; continue }
            if ($op.op -eq 'skip-existing') { continue }

            $localProblems = [System.Collections.Generic.List[string]]::new()
            $payload = Build-CcWritePayload -SourceRecord $src -Table $tbl -Environment $target `
                -EntitySetByLogical $ctx.EntitySetByLogical -SourceIndexes $ctx.SourceIndexes `
                -Maps $maps -SystemColumns $manifest.systemColumns -Problems ([ref]$localProblems)
            foreach ($p in $localProblems) { $problems.Add($p) | Out-Null }

            $altVal   = if ($tbl.alternateKey) { [string]$src.$($tbl.alternateKey) } else { $null }
            $tgtGuid  = $targetByKey[$op.table][$op.matchKey]
            $createOnce = ($tbl.move -eq 'create-once')

            if ($Mode -eq 'DryRun') {
                Write-Verbose "[dry-run] $($op.op) $($op.table) '$($op.matchKey)'"
                $written++
                continue
            }

            if (-not $PSCmdlet.ShouldProcess("$($op.table) '$($op.matchKey)' in $($target.Name)", $op.op)) { continue }

            try {
                Invoke-CcUpsert -Environment $target -Table $tbl -Payload $payload `
                    -AltKeyValue $altVal -TargetGuid $tgtGuid -CreateOnce:$createOnce | Out-Null
                $written++

                if ($tbl.async -and $op.op -eq 'create') {
                    $wsName = [string]$src.msdyn_name
                    if (-not (Wait-CcProvisioning -Environment $target -WorkstreamName $wsName -TimeoutSeconds $ProvisioningTimeoutSeconds)) {
                        $warnings.Add("Provisioning not confirmed for '$wsName'.") | Out-Null
                    }
                }

                if ($tbl.doubleWrite) {
                    # Second write lands dependency mappings for rulesets with context variables.
                    Start-Sleep -Seconds 2
                    Invoke-CcUpsert -Environment $target -Table $tbl -Payload $payload -AltKeyValue $altVal -TargetGuid $tgtGuid | Out-Null
                }
            }
            catch {
                $state = 'PartiallyFailed'
                $warnings.Add("FAILED $($op.table) '$($op.matchKey)': $($_.Exception.Message)") | Out-Null
                $stageResults["stage$stage"] = [pscustomobject]@{ state = 'Failed'; written = $written; warnings = $warnings }
                Write-CcRunResult -RunId $runId -State $state -Target $target.Id -Stages $stageResults `
                    -SnapshotPath $snapshotPath -Problems $problems -OutputDir $OutputDir -Mode $Mode
                Write-Warning "Run stopped at stage $stage. Roll back with Restore-CcRun -SnapshotPath '$snapshotPath'."
                return $script:CcLastRun
            }
        }

        $stageResults["stage$stage"] = [pscustomobject]@{ state = 'Succeeded'; written = $written; warnings = $warnings }
        Write-Host ("Stage {0}: {1} written{2}" -f $stage, $written, ($(if ($warnings.Count){" ($($warnings.Count) warnings)"}else{""}))) -ForegroundColor Green
    }

    Write-CcRunResult -RunId $runId -State $state -Target $target.Id -Stages $stageResults `
        -SnapshotPath $snapshotPath -Problems $problems -OutputDir $OutputDir -Mode $Mode
    return $script:CcLastRun
}

function Write-CcRunResult {
    param($RunId, $State, $Target, $Stages, $SnapshotPath, $Problems, $OutputDir, $Mode)
    $run = [pscustomobject]@{
        runId      = $RunId
        mode       = $Mode
        target     = $Target
        state      = $State
        snapshot   = $SnapshotPath
        stages     = $Stages
        problems   = $Problems
        finished   = (Get-Date).ToString('o')
    }
    $path = Join-Path $OutputDir "run-$RunId.json"
    $run | ConvertTo-Json -Depth 20 | Set-Content -Path $path -Encoding UTF8
    $script:CcLastRun = $run
    Write-Host "Run $RunId : $State. Details: $path" -ForegroundColor Cyan
    if ($Problems.Count -gt 0) {
        Write-Host "Problems flagged:" -ForegroundColor Yellow
        $Problems | Select-Object -Unique | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
    }
}
