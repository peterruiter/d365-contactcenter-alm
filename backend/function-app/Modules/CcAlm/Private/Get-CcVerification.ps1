function Get-CcExtraRefs {
    # Every record a diff found only in the target, as "table|key". Taken before a run writes, so the
    # check afterwards can tell records Dataverse added during the run from ones that were there.
    param([pscustomobject] $Diff)
    return @($Diff.tables | ForEach-Object {
            $t = $_.table
            $_.records | Where-Object status -eq 'ExtraInTarget' | ForEach-Object { "$t|$($_.matchKey)" }
        })
}

function Get-CcVerification {
    <#
    .SYNOPSIS
        Checks an applied run against a fresh compare: every record the run created, updated or
        linked should now be the same in the target as in the source. Reports each one that is not,
        with the settings that still differ, and the records that appeared in the target during the
        run without being in the source (what Dataverse provisions on its own for a new workstream).
    .PARAMETER Diff
        A compare of the same source and target, taken after the run finished writing.
    .PARAMETER Items
        The run's items.
    .PARAMETER ExtraBefore
        Get-CcExtraRefs of the compare taken before the run wrote anything.
    #>
    param(
        [Parameter(Mandatory)] [pscustomobject] $Diff,
        [object[]] $Items,
        [string[]] $ExtraBefore
    )

    $plans = $Diff._context.TablePlans
    $byRef = @{}
    foreach ($td in $Diff.tables) {
        foreach ($r in $td.records) { $byRef["$($td.table)|$($r.matchKey)"] = $r }
    }

    # One check per record, however many items (write, then link) it has.
    $written = [ordered]@{}
    foreach ($i in @($Items | Where-Object { $_ -and $_.outcome -in 'created', 'updated', 'linked' -and $_.matchKey })) {
        $ref = "$($i.table)|$($i.matchKey)"
        if (-not $written.Contains($ref)) { $written[$ref] = $i }
        elseif ($i.op -in 'create', 'update') { $written[$ref] = $i }
    }

    $differences = [System.Collections.Generic.List[object]]::new()
    $matched = 0
    foreach ($ref in $written.Keys) {
        $i = $written[$ref]
        $row = $byRef[$ref]
        $base = [ordered]@{ table = $i.table; tableLabel = $i.tableLabel; displayName = $i.displayName; context = $i.context }
        if (-not $row) {
            $differences.Add(($base + [ordered]@{ status = 'NotFound'; message = 'Not found in either environment when checked afterwards.'; fields = @() })) | Out-Null
            continue
        }
        switch ($row.status) {
            'Equal' { $matched++ }
            'Changed' {
                $attrs = if ($plans[$i.table]) { $plans[$i.table].TargetSchema.Attributes } else { @{} }
                $fields = @($row.fields | Where-Object { $_ } | ForEach-Object {
                        $bare = $_.name -replace '^_' -replace '_value$'
                        $a = $attrs[$bare]
                        $note = $null
                        if ($a -and $i.op -eq 'update' -and -not $a.Update) { $note = 'Dataverse does not allow changing this after the record is created.' }
                        elseif ($a -and $i.op -eq 'create' -and -not $a.Create) { $note = 'Dataverse does not allow setting this when a record is created, so the new record has its default. Change it in the target if it matters.' }
                        [ordered]@{ label = $_.label; source = $_.source; target = $_.target; note = $note }
                    })
                $differences.Add(($base + [ordered]@{ status = 'Changed'; message = 'Still differs from the source.'; fields = $fields })) | Out-Null
            }
            'MissingInTarget' {
                $differences.Add(($base + [ordered]@{ status = 'Missing'; message = 'Not found in the target, although it was written. Dataverse may have renamed or removed it.'; fields = @() })) | Out-Null
            }
            'Ambiguous' {
                $differences.Add(($base + [ordered]@{ status = 'Ambiguous'; message = $row.note; fields = @() })) | Out-Null
            }
            default {
                $differences.Add(($base + [ordered]@{ status = $row.status; message = "Its status is $($row.status)."; fields = @() })) | Out-Null
            }
        }
    }

    $before = @{}
    foreach ($r in @($ExtraBefore)) { if ($r) { $before[$r] = $true } }
    $added = [System.Collections.Generic.List[object]]::new()
    if ($null -ne $ExtraBefore) {
        foreach ($td in $Diff.tables) {
            foreach ($r in @($td.records | Where-Object status -eq 'ExtraInTarget')) {
                if ($before.ContainsKey("$($td.table)|$($r.matchKey)")) { continue }
                $added.Add([ordered]@{ table = $td.table; tableLabel = $td.label; displayName = $r.displayName; context = $r.context }) | Out-Null
            }
        }
    }

    return [ordered]@{
        state       = if ($differences.Count -eq 0) { 'Verified' } else { 'Differences' }
        checkedAt   = (Get-Date).ToString('o')
        checked     = $written.Count
        matched     = $matched
        differences = @($differences)
        added       = @($added)
        message     = $null
    }
}
