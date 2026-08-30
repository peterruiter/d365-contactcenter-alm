function New-CcPlan {
    <#
    .SYNOPSIS
        Turns a diff into an ordered list of write operations, respecting manifest order and stages.
        By default it plans every MissingInTarget and Changed record. Pass -Selection to limit it.
    .PARAMETER Selection
        Array of @{ table = 'msdyn_liveworkstream'; matchKey = 'msdyn_name=sales chat|...' }.
    .EXAMPLE
        $plan = New-CcPlan -Diff $diff
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [pscustomobject] $Diff,
        [object[]] $Selection
    )

    $manifest = $Diff._context.Manifest
    $orderByTable = @{}
    foreach ($t in $manifest.tables) { $orderByTable[$t.logicalName] = $t }

    $selected = $null
    if ($Selection) {
        $selected = @{}
        foreach ($s in $Selection) { $selected["$($s.table)|$($s.matchKey)"] = $true }
    }

    $ops = [System.Collections.Generic.List[object]]::new()
    $seq = 0

    # Walk tables in manifest order so parents precede children.
    foreach ($t in ($manifest.tables | Sort-Object order)) {
        if ($t.move -eq 'detect') { continue }
        $td = $Diff.tables | Where-Object table -eq $t.logicalName | Select-Object -First 1
        if (-not $td) { continue }

        foreach ($r in $td.records) {
            if ($r.status -ne 'MissingInTarget' -and $r.status -ne 'Changed') { continue }
            if ($selected -and -not $selected.ContainsKey("$($t.logicalName)|$($r.matchKey)")) { continue }

            $op = if ($r.status -eq 'MissingInTarget') { 'create' } else { 'update' }
            if ($t.move -eq 'create-once' -and $r.status -eq 'Changed') { $op = 'skip-existing' }

            $seq++
            $ops.Add([pscustomobject]@{
                seq         = $seq
                stage       = $t.stage
                order       = $t.order
                table       = $t.logicalName
                op          = $op
                matchKey    = $r.matchKey
                displayName = $r.displayName
            }) | Out-Null
        }
    }

    $plan = [pscustomobject]@{
        planId     = "pln_$([guid]::NewGuid().ToString('N').Substring(0,12))"
        source     = $Diff.source
        target     = $Diff.target
        created    = (Get-Date).ToString('o')
        operations = $ops
        _context   = $Diff._context
    }

    Write-Host "Plan $($plan.planId): $($ops.Count) operations across stages $((($ops.stage | Sort-Object -Unique) -join ', '))." -ForegroundColor Cyan
    return $plan
}
