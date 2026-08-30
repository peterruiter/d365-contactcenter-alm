function Get-CcComparableKey {
    param([pscustomobject] $Record, [pscustomobject] $Table, [hashtable] $EnvIndexes)
    $resolved = Resolve-CcLookupsToKeys -Record $Record -Table $Table -EnvIndexes $EnvIndexes
    return Get-CcNaturalKey -Record $Record -Table $Table -ResolvedLookups $resolved
}

function Get-CcDependsOn {
    <#
    .SYNOPSIS
        For one record, lists the other records it points at via manifest lookups: table plus the
        natural key of the referenced parent. Drives "select this, also select its dependencies" in
        the UI, and surfaces cross-table dependencies (e.g. a routing step's ruleset, a workstream's
        operating hour) that would otherwise only show up as a write-time failure. Also scans any
        guidBearingColumns text (e.g. a ruleset definition's embedded queue GUIDs) so those show up
        as dependencies too, not just explicit lookup columns.
    #>
    param([pscustomobject] $Record, [pscustomobject] $Table, [hashtable] $EnvIndexes, [hashtable] $SourceGuidToRef, [hashtable] $TableByLogical)

    $deps = [System.Collections.Generic.List[object]]::new()
    $seen = @{}

    foreach ($lk in $Table.lookups) {
        $valueCol = "_$($lk.column)_value"
        if ($Record.PSObject.Properties.Name -notcontains $valueCol) { continue }
        $guid = [string]$Record.$valueCol
        if (-not $guid) { continue }

        $refIdx = $EnvIndexes[$lk.target]
        $refTable = $TableByLogical[$lk.target]
        # The referenced record's RESOLVED key (Get-CcComparableKey), not the raw IdToKey - for a
        # table whose own matchKeys include a lookup column (msdyn_routingconfiguration, matched on
        # name plus its parent workstream), the raw key embeds that lookup's GUID as-is, which never
        # matches the same record's key elsewhere in the diff (built the same resolved way). An
        # unresolved dependency here means a "Requires" hint nobody could ever satisfy.
        if ($refIdx -and $refTable -and $refIdx.ById.ContainsKey($guid)) {
            $refKey = Get-CcComparableKey -Record $refIdx.ById[$guid] -Table $refTable -EnvIndexes $EnvIndexes
            $key = "$($lk.target)|$refKey"
            if (-not $seen.ContainsKey($key)) {
                $seen[$key] = $true
                $deps.Add([pscustomobject]@{ table = $lk.target; matchKey = $refKey }) | Out-Null
            }
        }
    }

    if ($Table.guidBearingColumns -and $SourceGuidToRef) {
        foreach ($col in $Table.guidBearingColumns) {
            if ($Record.PSObject.Properties.Name -notcontains $col) { continue }
            $text = [string]$Record.$col
            if (-not $text) { continue }
            foreach ($guid in (Get-CcGuids -Text $text)) {
                if (-not $SourceGuidToRef.ContainsKey($guid)) { continue }
                $ref = $SourceGuidToRef[$guid]
                $key = "$($ref.Entity)|$($ref.Key)"
                if (-not $seen.ContainsKey($key)) {
                    $seen[$key] = $true
                    $deps.Add([pscustomobject]@{ table = $ref.Entity; matchKey = $ref.Key }) | Out-Null
                }
            }
        }
    }

    return $deps
}

function Get-CcDisplayName {
    <#
    .SYNOPSIS
        The friendly label for one record, when the table names a displayColumn (e.g. msdyn_name)
        distinct from what its matchKey is built from (e.g. msdyn_uniquename), or a displayTemplate
        for tables with no readable field of their own (e.g. an ordered step, labelled "Step {N}").
        Falls back to no label - the UI then just shows the matchKey - for tables where the match key
        is already readable, or where the record's own fields don't have anything better to say.
    #>
    param([pscustomobject] $Record, [pscustomobject] $Table)

    if ($Table.displayTemplate) {
        $evaluator = [System.Text.RegularExpressions.MatchEvaluator]{
            param($m)
            $col = $m.Groups[1].Value
            if ($Record.PSObject.Properties.Name -contains $col) { return [string]$Record.$col }
            return $m.Value
        }
        return [regex]::Replace($Table.displayTemplate, '\{(\w+)\}', $evaluator)
    }

    if (-not $Table.displayColumn) { return $null }
    if ($Record.PSObject.Properties.Name -notcontains $Table.displayColumn) { return $null }
    $val = [string]$Record.($Table.displayColumn)
    if (-not $val) { return $null }
    return $val
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
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $SourceRecords,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $TargetRecords,
        [Parameter(Mandatory)] [hashtable] $SourceIndexes,
        [Parameter(Mandatory)] [hashtable] $TargetIndexes,
        [Parameter(Mandatory)] [string[]] $SystemColumns,
        [hashtable] $SourceGuidToRef,
        [hashtable] $TableByLogical
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
            $deps = Get-CcDependsOn -Record $s -Table $Table -EnvIndexes $SourceIndexes -SourceGuidToRef $SourceGuidToRef -TableByLogical $TableByLogical
            $displayName = Get-CcDisplayName -Record $s -Table $Table
            $records.Add([pscustomobject]@{ matchKey = $key; status = 'MissingInTarget'; fields = @(); dependsOn = @($deps); displayName = $displayName })
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
                # Compare the referenced record's resolved natural key, not the raw GUID. Using the
                # referenced table's own raw IdToKey here (rather than its resolved comparable key)
                # would be wrong whenever that table's own matchKeys include a lookup column - e.g. a
                # routing config matched on name plus its parent workstream - because IdToKey embeds
                # that lookup's GUID as-is, and source/target use different GUIDs for "the same"
                # parent, making every such reference look changed even when nothing really is.
                $lk = $Table.lookups | Where-Object { "_$($_.column)_value" -eq $col } | Select-Object -First 1
                if ($lk) {
                    $refTable = $TableByLogical[$lk.target]
                    $svKey = if ($sv -and $refTable -and $SourceIndexes[$lk.target] -and $SourceIndexes[$lk.target].ById.ContainsKey([string]$sv)) {
                        Get-CcComparableKey -Record $SourceIndexes[$lk.target].ById[[string]$sv] -Table $refTable -EnvIndexes $SourceIndexes
                    } else { $null }
                    $tvKey = if ($tv -and $refTable -and $TargetIndexes[$lk.target] -and $TargetIndexes[$lk.target].ById.ContainsKey([string]$tv)) {
                        Get-CcComparableKey -Record $TargetIndexes[$lk.target].ById[[string]$tv] -Table $refTable -EnvIndexes $TargetIndexes
                    } else { $null }
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
        $deps = if ($status -eq 'Changed') { Get-CcDependsOn -Record $s -Table $Table -EnvIndexes $SourceIndexes -SourceGuidToRef $SourceGuidToRef -TableByLogical $TableByLogical } else { @() }
        $displayName = Get-CcDisplayName -Record $s -Table $Table
        $records.Add([pscustomobject]@{ matchKey = $key; status = $status; fields = $fields; dependsOn = @($deps); displayName = $displayName }) | Out-Null
    }

    foreach ($tk in $targetByKey.Keys) {
        if (-not $sourceKeys.ContainsKey($tk)) {
            $displayName = Get-CcDisplayName -Record $targetByKey[$tk] -Table $Table
            $records.Add([pscustomobject]@{ matchKey = $tk; status = 'ExtraInTarget'; fields = @(); dependsOn = @(); displayName = $displayName }) | Out-Null
        }
    }

    return [pscustomobject]@{
        table   = $Table.logicalName
        records = $records
    }
}
