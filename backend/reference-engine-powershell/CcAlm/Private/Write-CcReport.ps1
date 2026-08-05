function Write-CcConsoleSummary {
    param([pscustomobject] $Diff)

    Write-Host ''
    Write-Host "Compare: $($Diff.source) -> $($Diff.target)" -ForegroundColor Cyan
    Write-Host ("{0,-42} {1,7} {2,7} {3,7} {4,7}" -f 'Table','Missing','Extra','Changed','Equal')
    Write-Host ('-' * 74)

    foreach ($t in $Diff.tables) {
        $m = ($t.records | Where-Object status -eq 'MissingInTarget').Count
        $e = ($t.records | Where-Object status -eq 'ExtraInTarget').Count
        $c = ($t.records | Where-Object status -eq 'Changed').Count
        $q = ($t.records | Where-Object status -eq 'Equal').Count
        if (($m + $e + $c) -eq 0) { continue }
        Write-Host ("{0,-42} {1,7} {2,7} {3,7} {4,7}" -f $t.table, $m, $e, $c, $q)
    }

    Write-Host ('-' * 74)
    Write-Host ("{0,-42} {1,7} {2,7} {3,7} {4,7}" -f 'TOTAL', $Diff.summary.missingInTarget, $Diff.summary.extraInTarget, $Diff.summary.changed, $Diff.summary.equal) -ForegroundColor White

    if ($Diff.detectOnly.Count -gt 0) {
        Write-Host ''
        Write-Host "Detect-only (cannot move as data, provision in target):" -ForegroundColor Yellow
        foreach ($d in $Diff.detectOnly) {
            Write-Host "  [$($d.type)] $($d.record): $($d.message)" -ForegroundColor Yellow
        }
    }
    Write-Host ''
}

function Write-CcMarkdownReport {
    param([pscustomobject] $Diff, [string] $Path)

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("# Contact Center config diff")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("Source: **$($Diff.source)**  ->  Target: **$($Diff.target)**  ")
    [void]$sb.AppendLine("Generated: $($Diff.generated)")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("| Metric | Count |")
    [void]$sb.AppendLine("|---|---|")
    [void]$sb.AppendLine("| Missing in target | $($Diff.summary.missingInTarget) |")
    [void]$sb.AppendLine("| Extra in target | $($Diff.summary.extraInTarget) |")
    [void]$sb.AppendLine("| Changed | $($Diff.summary.changed) |")
    [void]$sb.AppendLine("| Equal | $($Diff.summary.equal) |")
    [void]$sb.AppendLine("")

    foreach ($t in $Diff.tables) {
        $rows = $t.records | Where-Object status -ne 'Equal'
        if (-not $rows) { continue }
        [void]$sb.AppendLine("## $($t.table)")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("| Record | Status | Field deltas |")
        [void]$sb.AppendLine("|---|---|---|")
        foreach ($r in $rows) {
            $delta = ''
            if ($r.fields -and $r.fields.Count -gt 0) {
                $delta = ($r.fields | ForEach-Object { "$($_.name): '$($_.source)' -> '$($_.target)'" }) -join '; '
            }
            [void]$sb.AppendLine("| $($r.matchKey) | $($r.status) | $delta |")
        }
        [void]$sb.AppendLine("")
    }

    if ($Diff.detectOnly.Count -gt 0) {
        [void]$sb.AppendLine("## Detect-only gaps")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("| Type | Record | Action |")
        [void]$sb.AppendLine("|---|---|---|")
        foreach ($d in $Diff.detectOnly) {
            [void]$sb.AppendLine("| $($d.type) | $($d.record) | $($d.message) |")
        }
        [void]$sb.AppendLine("")
    }

    Set-Content -Path $Path -Value $sb.ToString() -Encoding UTF8
}
