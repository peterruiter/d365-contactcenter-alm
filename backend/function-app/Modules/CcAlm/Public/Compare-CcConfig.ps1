function Compare-CcConfig {
    <#
    .SYNOPSIS
        Reads every manifest table from source and target, diffs them, and returns a diff model.
        Writes a markdown report and a JSON diff when -OutputDir is given.
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
    $tablesToRead = $manifest.tables
    if ($Tables) { $tablesToRead = $manifest.tables | Where-Object { $Tables -contains $_.logicalName } }

    $entitySetByLogical = @{}
    foreach ($t in $manifest.tables) { $entitySetByLogical[$t.logicalName] = $t.entitySet }

    Write-Verbose "Reading source ($($source.Name)) and target ($($target.Name))."
    $sourceRecordsByTable = @{}
    $targetRecordsByTable = @{}
    $sourceIndexes = @{}
    $targetIndexes = @{}

    foreach ($t in $tablesToRead) {
        $sr = @(Get-CcRecords -Environment $source -Table $t)
        $tr = @(Get-CcRecords -Environment $target -Table $t)
        $sourceRecordsByTable[$t.logicalName] = $sr
        $targetRecordsByTable[$t.logicalName] = $tr
        $sourceIndexes[$t.logicalName] = Build-CcIndex -Records $sr -Table $t
        $targetIndexes[$t.logicalName] = Build-CcIndex -Records $tr -Table $t
    }

    $maps = Build-CcGlobalMaps -SourceIndexes $sourceIndexes -TargetIndexes $targetIndexes

    $tableDiffs = [System.Collections.Generic.List[object]]::new()
    foreach ($t in $tablesToRead) {
        if ($t.move -eq 'detect') { continue }
        $td = Compare-CcTable -Table $t `
            -SourceRecords $sourceRecordsByTable[$t.logicalName] `
            -TargetRecords $targetRecordsByTable[$t.logicalName] `
            -SourceIndexes $sourceIndexes -TargetIndexes $targetIndexes `
            -SystemColumns $manifest.systemColumns -SourceGuidToRef $maps.SourceGuidToRef
        $tableDiffs.Add($td) | Out-Null
    }

    $detect = Get-CcDetectOnly -Manifest $manifest -SourceRecordsByTable $sourceRecordsByTable -TargetRecordsByTable $targetRecordsByTable

    $summary = [pscustomobject]@{
        missingInTarget = (@($tableDiffs.records | Where-Object status -eq 'MissingInTarget')).Count
        extraInTarget   = (@($tableDiffs.records | Where-Object status -eq 'ExtraInTarget')).Count
        changed         = (@($tableDiffs.records | Where-Object status -eq 'Changed')).Count
        equal           = (@($tableDiffs.records | Where-Object status -eq 'Equal')).Count
    }

    $diff = [pscustomobject]@{
        source     = $source.Id
        target     = $target.Id
        generated  = (Get-Date).ToString('o')
        summary    = $summary
        tables     = $tableDiffs
        detectOnly = $detect
        # kept for the plan/apply step so they do not re-read
        _context   = [pscustomobject]@{
            SourceRecordsByTable = $sourceRecordsByTable
            TargetRecordsByTable = $targetRecordsByTable
            SourceIndexes        = $sourceIndexes
            TargetIndexes        = $targetIndexes
            Maps                 = $maps
            EntitySetByLogical   = $entitySetByLogical
            Manifest             = $manifest
        }
    }

    Write-CcConsoleSummary -Diff $diff

    if ($OutputDir) {
        if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir | Out-Null }
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        Write-CcMarkdownReport -Diff $diff -Path (Join-Path $OutputDir "diff-$($source.Id)-to-$($target.Id)-$stamp.md")
        $diff | Select-Object source, target, generated, summary, tables, detectOnly |
            ConvertTo-Json -Depth 40 | Set-Content -Path (Join-Path $OutputDir "diff-$($source.Id)-to-$($target.Id)-$stamp.json") -Encoding UTF8
        Write-Host "Reports written to $OutputDir" -ForegroundColor Green
    }

    return $diff
}
