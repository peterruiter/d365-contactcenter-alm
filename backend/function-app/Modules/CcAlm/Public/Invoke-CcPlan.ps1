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
            -TargetIndexes $ctx.TargetIndexes -TableByLogical $tableByLogical -Path $snapshotPath | Out-Null
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
            $built = Build-CcWritePayload -SourceRecord $src -Table $tbl -Environment $target `
                -EntitySetByLogical $ctx.EntitySetByLogical -SourceIndexes $ctx.SourceIndexes `
                -Maps $maps -SystemColumns $manifest.systemColumns -Problems ([ref]$localProblems) `
                -TableByLogical $tableByLogical
            foreach ($p in $localProblems) { $problems.Add($p) | Out-Null }
            $payload = $built.Payload

            $tgtGuid  = $targetByKey[$op.table][$op.matchKey]
            $createOnce = ($tbl.move -eq 'create-once')

            if ($built.Blocked) {
                # A guidBearingColumns field (e.g. a ruleset definition) references a record that
                # hasn't landed in target yet. Dataverse rejects that outright, so skip the write
                # instead of burning it and aborting every later stage - the problems list above
                # names what's missing; re-run once the referenced records are migrated. This is not
                # a full success either: some selected records did not move, so the overall run state
                # must say so rather than reporting a plain 'Succeeded' with the skips buried below.
                $warnings.Add("SKIPPED $($op.table) '$($op.matchKey)': unresolved references, see problems list.") | Out-Null
                if ($state -eq 'Succeeded') { $state = 'PartiallyFailed' }
                continue
            }

            if ($Mode -eq 'DryRun') {
                Write-Verbose "[dry-run] $($op.op) $($op.table) '$($op.matchKey)'"
                $written++
                continue
            }

            if (-not $PSCmdlet.ShouldProcess("$($op.table) '$($op.matchKey)' in $($target.Name)", $op.op)) { continue }

            try {
                $writeResult = Invoke-CcUpsert -Environment $target -Table $tbl -Payload $payload `
                    -TargetGuid $tgtGuid -CreateOnce:$createOnce
                $written++

                # Land the GUID this record now has in target back into the shared lookup maps right
                # away, so a later operation in this same run that depends on it - an explicit lookup,
                # or an embedded GUID inside a guidBearingColumns field - can resolve it immediately
                # instead of needing a second apply run. Without this, $maps still reflects target as
                # it was before this run started, so anything created a few operations ago looks like
                # it "doesn't exist yet" to whatever references it next.
                $writtenGuid = if ($tgtGuid) { $tgtGuid } else { Get-CcRecordId -Record $writeResult -Table $tbl }
                if ($writtenGuid) {
                    $maps.TargetKeyToGuid["$($op.table)|$($op.matchKey)"] = $writtenGuid
                    $targetByKey[$op.table][$op.matchKey] = $writtenGuid
                }

                if ($tbl.async -and $op.op -eq 'create') {
                    $wsName = [string]$src.msdyn_name
                    if (-not (Wait-CcProvisioning -Environment $target -WorkstreamName $wsName -TimeoutSeconds $ProvisioningTimeoutSeconds)) {
                        $warnings.Add("Provisioning not confirmed for '$wsName'.") | Out-Null
                    }
                }

                if ($tbl.doubleWrite) {
                    # Second write lands dependency mappings for rulesets with context variables.
                    # It must target the GUID this record actually landed at - reusing the original
                    # $tgtGuid (null on a create) re-POSTs the same record and Dataverse rejects the
                    # duplicate key. On create that GUID only exists in the first write's response.
                    if ($writtenGuid) {
                        Start-Sleep -Seconds 2
                        Invoke-CcUpsert -Environment $target -Table $tbl -Payload $payload -TargetGuid $writtenGuid | Out-Null
                    }
                    else {
                        $warnings.Add("Could not resolve the written GUID for $($op.table) '$($op.matchKey)' to land its second write.") | Out-Null
                    }
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
