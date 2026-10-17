function Get-CcRecordTitle {
    param($Record)
    if ($Record.context) { return "$($Record.context) › $($Record.displayName)" }
    return $Record.displayName
}

function Write-CcConsoleSummary {
    param([pscustomobject] $Diff)

    Write-Host ''
    Write-Host "Compare: $($Diff.source) -> $($Diff.target)" -ForegroundColor Cyan
    Write-Host ("{0,-34} {1,7} {2,7} {3,7} {4,7} {5,9}" -f 'Table', 'New', 'Changed', 'Extra', 'Same', 'Ambiguous')
    Write-Host ('-' * 77)
    foreach ($t in $Diff.tables) {
        # @() around each filter: a single match is otherwise a lone object without a Count.
        $n = @($t.records | Where-Object status -eq 'MissingInTarget').Count
        $c = @($t.records | Where-Object status -eq 'Changed').Count
        $e = @($t.records | Where-Object status -eq 'ExtraInTarget').Count
        $q = @($t.records | Where-Object status -eq 'Equal').Count
        $a = @($t.records | Where-Object status -eq 'Ambiguous').Count
        if (($n + $c + $e + $a) -eq 0) { continue }
        Write-Host ("{0,-34} {1,7} {2,7} {3,7} {4,7} {5,9}" -f $t.label, $n, $c, $e, $q, $a)
    }
    Write-Host ('-' * 77)
    $s = $Diff.summary
    Write-Host ("{0,-34} {1,7} {2,7} {3,7} {4,7} {5,9}" -f 'Total', $s.missingInTarget, $s.changed, $s.extraInTarget, $s.equal, $s.ambiguous) -ForegroundColor White

    foreach ($n in @($Diff.notices)) { Write-Host "  note: $($n.message)" -ForegroundColor DarkYellow }
    foreach ($d in @($Diff.detectOnly)) { Write-Host "  manual: [$($d.label)] $($d.record): $($d.message)" -ForegroundColor Yellow }
    Write-Host ''
}

function Write-CcMarkdownReport {
    param([pscustomobject] $Diff, [string] $Path)

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("# Contact Center configuration: $($Diff.source) compared with $($Diff.target)")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("Generated $($Diff.generated)")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('| | Records |')
    [void]$sb.AppendLine('|---|---|')
    [void]$sb.AppendLine("| New in target | $($Diff.summary.missingInTarget) |")
    [void]$sb.AppendLine("| Changed | $($Diff.summary.changed) |")
    [void]$sb.AppendLine("| Only in target | $($Diff.summary.extraInTarget) |")
    [void]$sb.AppendLine("| Same | $($Diff.summary.equal) |")
    [void]$sb.AppendLine("| Ambiguous | $($Diff.summary.ambiguous) |")
    [void]$sb.AppendLine('')

    $statusText = @{ MissingInTarget = 'New'; Changed = 'Changed'; ExtraInTarget = 'Only in target'; Ambiguous = 'Ambiguous' }
    foreach ($t in $Diff.tables) {
        $rows = @($t.records | Where-Object status -ne 'Equal')
        if (-not $rows) { continue }
        [void]$sb.AppendLine("## $($t.label)")
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('| Record | Status | What differs |')
        [void]$sb.AppendLine('|---|---|---|')
        foreach ($r in $rows) {
            $delta = if ($r.note) { $r.note } else { (@($r.fields) | ForEach-Object { if ($_.kind -eq 'definition') { "$($_.label): $($_.source)" } else { "$($_.label): '$($_.target)' -> '$($_.source)'" } }) -join '; ' }
            [void]$sb.AppendLine("| $((Get-CcRecordTitle $r) -replace '\|', '\|') | $($statusText[$r.status]) | $($delta -replace '\|', '\|') |")
        }
        [void]$sb.AppendLine('')
    }

    if (@($Diff.detectOnly).Count -gt 0) {
        [void]$sb.AppendLine('## Set up by hand in the target')
        [void]$sb.AppendLine('')
        foreach ($d in $Diff.detectOnly) { [void]$sb.AppendLine("- **$($d.label): $($d.record)**. $($d.message)") }
        [void]$sb.AppendLine('')
    }
    Set-Content -Path $Path -Value $sb.ToString() -Encoding UTF8
}
