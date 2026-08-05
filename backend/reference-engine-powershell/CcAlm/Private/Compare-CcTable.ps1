function Get-CcComparableKey {
    param([pscustomobject] $Record, [pscustomobject] $Table, [hashtable] $EnvIndexes)
    $resolved = Resolve-CcLookupsToKeys -Record $Record -Table $Table -EnvIndexes $EnvIndexes
    return Get-CcNaturalKey -Record $Record -Table $Table -ResolvedLookups $resolved
}

function Compare-CcTable {
    <#
    .SYNOPSIS
        Diffs one table between source and target. Classifies each record as MissingInTarget,
        ExtraInTarget, Changed, or Equal, with a field-level delta for Changed rows.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [pscustomobject] $Table,
        [Parameter(Mandatory)] [object[]] $SourceRecords,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $TargetRecords,
        [Parameter(Mandatory)] [hashtable] $SourceIndexes,
        [Parameter(Mandatory)] [hashtable] $TargetIndexes,
        [Parameter(Mandatory)] [string[]] $SystemColumns,
        [hashtable] $SourceGuidToRef
    )

    $skip = @($SystemColumns)
    if ($Table.skipColumns) { $skip += $Table.skipColumns }

    # Build target lookup by comparable key.
    $targetByKey = @{}
    foreach ($t in $TargetRecords) {
        $k = Get-CcComparableKey -Record $t -Table $Table -EnvIndexes $TargetIndexes
        $targetByKey[$k] = $t
    }
    $sourceKeys = @{}

    $records = [System.Collections.Generic.List[object]]::new()

    foreach ($s in $SourceRecords) {
        $key = Get-CcComparableKey -Record $s -Table $Table -EnvIndexes $SourceIndexes
        $sourceKeys[$key] = $true

        if (-not $targetByKey.ContainsKey($key)) {
            $records.Add([pscustomobject]@{ matchKey = $key; status = 'MissingInTarget'; fields = @() })
            continue
        }

        $t = $targetByKey[$key]
        $fields = [System.Collections.Generic.List[object]]::new()

        foreach ($col in $Table.select) {
            $bare = $col -replace '^_' -replace '_value$'
            if ($skip -contains $col -or $skip -contains $bare) { continue }
            if ($col -like '*id' -and $col -eq "$($Table.logicalName)id") { continue }  # primary key

            $isLookup = $col -match '^_.*_value$'
            $isGuidBearing = $Table.guidBearingColumns -and ($Table.guidBearingColumns -contains $col)

            $sv = $s.$col
            $tv = $t.$col

            if ($isLookup) {
                # Compare the referenced natural key, not the raw GUID.
                $lk = $Table.lookups | Where-Object { "_$($_.column)_value" -eq $col } | Select-Object -First 1
                if ($lk) {
                    $svKey = if ($sv -and $SourceIndexes[$lk.target]) { $SourceIndexes[$lk.target].IdToKey[[string]$sv] } else { $null }
                    $tvKey = if ($tv -and $TargetIndexes[$lk.target]) { $TargetIndexes[$lk.target].IdToKey[[string]$tv] } else { $null }
                    if ($svKey -ne $tvKey) {
                        $fields.Add([pscustomobject]@{ name = $col; source = $svKey; target = $tvKey }) | Out-Null
                    }
                    continue
                }
            }

            if ($isGuidBearing) {
                $sNorm = (ConvertTo-CcNormalisedDefinition -Definition ([string]$sv) -GuidToRef $SourceGuidToRef).Text
                $tNorm = (ConvertTo-CcNormalisedDefinition -Definition ([string]$tv) -GuidToRef @{}).Text
                # Target normalisation uses its own map in the caller; here a plain compare on source-normalised
                # text catches content drift. Exact target GUID identity is handled at write time.
                if ($sNorm -ne ([string]$tv) -and $sNorm -ne $tNorm) {
                    $fields.Add([pscustomobject]@{ name = $col; source = '<ruleset definition>'; target = '<differs>' }) | Out-Null
                }
                continue
            }

            if ("$sv" -ne "$tv") {
                $fields.Add([pscustomobject]@{ name = $col; source = $sv; target = $tv }) | Out-Null
            }
        }

        $status = if ($fields.Count -gt 0) { 'Changed' } else { 'Equal' }
        $records.Add([pscustomobject]@{ matchKey = $key; status = $status; fields = $fields }) | Out-Null
    }

    foreach ($tk in $targetByKey.Keys) {
        if (-not $sourceKeys.ContainsKey($tk)) {
            $records.Add([pscustomobject]@{ matchKey = $tk; status = 'ExtraInTarget'; fields = @() }) | Out-Null
        }
    }

    return [pscustomobject]@{
        table   = $Table.logicalName
        records = $records
    }
}
