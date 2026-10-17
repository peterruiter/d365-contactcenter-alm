function Compare-CcConfig {
    <#
    .SYNOPSIS
        Reads every manifest table from source and target, pairs the records and diffs them.
        Returns a diff model; writes a markdown report and a JSON diff when -OutputDir is given.
    .EXAMPLE
        $diff = Compare-CcConfig -Environments $envs -SourceId acc -TargetId prod -OutputDir ./out
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object[]] $Environments,
        [Parameter(Mandatory)] [string] $SourceId,
        [Parameter(Mandatory)] [string] $TargetId,
        [string] $ManifestPath = (Get-CcDefaultManifestPath),
        [string[]] $Tables,
        [string] $OutputDir
    )

    $source = $Environments | Where-Object Id -eq $SourceId | Select-Object -First 1
    $target = $Environments | Where-Object Id -eq $TargetId | Select-Object -First 1
    if (-not $source) { throw "Source environment '$SourceId' not found." }
    if (-not $target) { throw "Target environment '$TargetId' not found." }

    $manifest = Get-CcManifest -Path $ManifestPath
    $tableByLogical = @{}
    foreach ($t in $manifest.tables) { $tableByLogical[$t.logicalName] = $t }

    # Every table is read, even when -Tables narrows the diff: children are keyed by their parents
    # and lookups resolve through them, so a partial read would mis-key the tables you asked for.
    $tablePlans = @{}
    $notices = [System.Collections.Generic.List[object]]::new()
    foreach ($t in $manifest.tables) {
        $ss = Get-CcTableSchema -Environment $source -LogicalName $t.logicalName
        $ts = Get-CcTableSchema -Environment $target -LogicalName $t.logicalName
        $plan = Resolve-CcTablePlan -Table $t -SourceSchema $ss -TargetSchema $ts -Manifest $manifest -TableByLogical $tableByLogical
        $tablePlans[$t.logicalName] = $plan
        if (-not $plan.Usable) {
            if ($t.move -eq 'reference') { continue }
            $notices.Add([pscustomobject]@{ severity = 'info'; table = $t.logicalName; message = $plan.Reason }) | Out-Null
        }
        elseif ($plan.MissingInTarget.Count -gt 0) {
            $labels = @($plan.MissingInTarget | ForEach-Object { Get-CcColumnLabel $plan $_ } | Select-Object -First 6)
            $more = if ($plan.MissingInTarget.Count -gt 6) { " and $($plan.MissingInTarget.Count - 6) more" } else { '' }
            $notices.Add([pscustomobject]@{
                    severity = 'warning'; table = $t.logicalName
                    message  = "The target has an older version of $(Get-CcTableLabel $t): $($labels -join ', ')$more do not exist there and will not be copied."
                }) | Out-Null
        }
    }

    Write-Verbose "Reading source ($($source.Name)) and target ($($target.Name))."
    $sourceRecords = @{}
    $targetRecords = @{}
    foreach ($t in $manifest.tables) {
        $plan = $tablePlans[$t.logicalName]
        if (-not $plan.Usable) { $sourceRecords[$t.logicalName] = @(); $targetRecords[$t.logicalName] = @(); continue }
        $sr = @(Get-CcRecords -Environment $source -EntitySet $plan.SourceEntitySet -Select $plan.Select)
        $tr = @(Get-CcRecords -Environment $target -EntitySet $plan.EntitySet -Select $plan.Select)
        if ($t.personalFilterColumn) {
            # Personal and system queues: one per user, auto-provisioned, never configuration.
            $col = $t.personalFilterColumn
            $sr = @($sr | Where-Object { $_.$col -eq $true })
            $tr = @($tr | Where-Object { $_.$col -eq $true })
        }
        $sourceRecords[$t.logicalName] = $sr
        $targetRecords[$t.logicalName] = $tr
    }

    $srcData = New-CcEnvData -Side 'source' -RecordsByTable $sourceRecords -TablePlans $tablePlans
    $tgtData = New-CcEnvData -Side 'target' -RecordsByTable $targetRecords -TablePlans $tablePlans
    Set-CcKeys -Source $srcData -Target $tgtData -Tables $manifest.tables -TablePlans $tablePlans
    $maps = Build-CcMaps -Source $srcData -Target $tgtData -TablePlans $tablePlans

    $tableDiffs = [System.Collections.Generic.List[object]]::new()
    foreach ($t in $manifest.tables) {
        if ($t.move -in 'detect', 'reference') { continue }
        if ($Tables -and $Tables -notcontains $t.logicalName) { continue }
        $plan = $tablePlans[$t.logicalName]
        if (-not $plan.Usable) { continue }
        $td = Compare-CcTable -TablePlan $plan -Source $srcData -Target $tgtData -Maps $maps -TablePlans $tablePlans
        $tableDiffs.Add($td) | Out-Null
    }

    $detect = Get-CcDetectOnly -Manifest $manifest -Source $srcData -Target $tgtData -TablePlans $tablePlans

    $all = @($tableDiffs | ForEach-Object { $_.records } | ForEach-Object { $_ })
    $summary = [pscustomobject]@{
        missingInTarget = @($all | Where-Object status -eq 'MissingInTarget').Count
        extraInTarget   = @($all | Where-Object status -eq 'ExtraInTarget').Count
        changed         = @($all | Where-Object status -eq 'Changed').Count
        equal           = @($all | Where-Object status -eq 'Equal').Count
        ambiguous       = @($all | Where-Object status -eq 'Ambiguous').Count
    }

    $diff = [pscustomobject]@{
        diffId     = "dif_$([guid]::NewGuid().ToString('N').Substring(0, 12))"
        source     = $source.Id
        target     = $target.Id
        generated  = (Get-Date).ToString('o')
        summary    = $summary
        tables     = $tableDiffs
        detectOnly = @($detect | Where-Object { $_ })
        notices    = @($notices)
        # Kept for plan and run, so they do not read both environments again.
        _context   = [pscustomobject]@{
            Manifest   = $manifest
            TablePlans = $tablePlans
            Source     = $srcData
            Target     = $tgtData
            Maps       = $maps
        }
    }

    Write-CcConsoleSummary -Diff $diff

    if ($OutputDir) {
        if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir | Out-Null }
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        Write-CcMarkdownReport -Diff $diff -Path (Join-Path $OutputDir "diff-$($source.Id)-to-$($target.Id)-$stamp.md")
        $diff | Select-Object diffId, source, target, generated, summary, tables, detectOnly, notices |
            ConvertTo-Json -Depth 40 | Set-Content -Path (Join-Path $OutputDir "diff-$($source.Id)-to-$($target.Id)-$stamp.json") -Encoding UTF8
        Write-Host "Reports written to $OutputDir" -ForegroundColor Green
    }

    return $diff
}
