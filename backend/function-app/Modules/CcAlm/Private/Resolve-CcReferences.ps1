function Build-CcGlobalMaps {
    <#
    .SYNOPSIS
        Builds the maps that drive cross-environment matching and GUID remapping.
          SourceGuidToRef : sourceGuid -> @{ Entity; Key }
          TargetKeyToGuid : "entity|naturalKey" -> targetGuid
        Both Key/naturalKey values are the fully resolved comparable key (Get-CcComparableKey), not
        Build-CcIndex's raw IdToKey. For a table whose own matchKeys include a lookup column (for
        example msdyn_routingconfiguration, matched on name plus its parent workstream), the raw
        IdToKey embeds that lookup's GUID as-is - a different, environment-specific GUID on each
        side, so it can never agree between source and target. The resolved key instead embeds the
        parent's own natural key (its name, say), which is the same string on both sides whenever
        the parent itself matches - the only way "entity|naturalKey" can actually line up here.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [hashtable] $SourceIndexes,
        [Parameter(Mandatory)] [hashtable] $TargetIndexes,
        [Parameter(Mandatory)] [hashtable] $SourceRecordsByTable,
        [Parameter(Mandatory)] [hashtable] $TargetRecordsByTable,
        [Parameter(Mandatory)] [hashtable] $TableByLogical
    )

    $sourceGuidToRef = @{}
    foreach ($logical in $SourceIndexes.Keys) {
        $tbl = $TableByLogical[$logical]
        if (-not $tbl) { continue }
        foreach ($r in $SourceRecordsByTable[$logical]) {
            $guid = Get-CcRecordId -Record $r -Table $tbl
            if (-not $guid) { continue }
            $key = Get-CcComparableKey -Record $r -Table $tbl -EnvIndexes $SourceIndexes
            $sourceGuidToRef[$guid] = @{ Entity = $logical; Key = $key }
        }
    }

    $targetKeyToGuid = @{}
    foreach ($logical in $TargetIndexes.Keys) {
        $tbl = $TableByLogical[$logical]
        if (-not $tbl) { continue }
        foreach ($r in $TargetRecordsByTable[$logical]) {
            $guid = Get-CcRecordId -Record $r -Table $tbl
            if (-not $guid) { continue }
            $key = Get-CcComparableKey -Record $r -Table $tbl -EnvIndexes $TargetIndexes
            $targetKeyToGuid["$logical|$key"] = $guid
        }
    }

    return @{
        SourceGuidToRef = $sourceGuidToRef
        TargetKeyToGuid = $targetKeyToGuid
    }
}

function Resolve-CcLookupsToKeys {
    <#
    .SYNOPSIS
        For one record, resolves each manifest lookup column (_x_value GUID) to the referenced
        record's natural key, using the per-environment indexes. Returns a hashtable
        matchKeyColumn -> resolvedKey so records compare equal across environments.
    #>
    param(
        [pscustomobject] $Record,
        [pscustomobject] $Table,
        [hashtable] $EnvIndexes
    )

    $resolved = @{}
    foreach ($lk in $Table.lookups) {
        $valueCol = "_$($lk.column)_value"
        if ($Record.PSObject.Properties.Name -notcontains $valueCol) { continue }
        $guid = [string]$Record.$valueCol
        if (-not $guid) { $resolved[$valueCol] = $null; continue }

        $refIdx = $EnvIndexes[$lk.target]
        if ($refIdx -and $refIdx.IdToKey.ContainsKey($guid)) {
            $resolved[$valueCol] = $refIdx.IdToKey[$guid]
        }
        else {
            $resolved[$valueCol] = "UNRESOLVED:$guid"
        }
    }
    return $resolved
}

function Get-CcGuids {
    param([string] $Text)
    if (-not $Text) { return @() }
    $pattern = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
    return [regex]::Matches($Text, $pattern) | ForEach-Object { $_.Value.ToLowerInvariant() } | Select-Object -Unique
}

function ConvertTo-CcNormalisedDefinition {
    <#
    .SYNOPSIS
        Normalises a ruleset definition JSON string for cross-environment comparison by replacing
        embedded GUIDs with {entity:key} tokens. Two environments then compare equal on rule content.
        Unknown GUIDs stay as-is and are reported.
    #>
    param(
        [string] $Definition,
        [hashtable] $GuidToRef
    )
    if (-not $Definition) { return @{ Text = $Definition; Unknown = @() } }

    $unknown = [System.Collections.Generic.List[string]]::new()
    $text = $Definition
    foreach ($guid in (Get-CcGuids -Text $Definition)) {
        if ($GuidToRef.ContainsKey($guid)) {
            $ref = $GuidToRef[$guid]
            $text = $text.Replace($guid, "{$($ref.Entity):$($ref.Key)}")
        }
        else {
            $unknown.Add($guid) | Out-Null
        }
    }
    return @{ Text = $text; Unknown = $unknown }
}

function ConvertTo-CcTargetDefinition {
    <#
    .SYNOPSIS
        Rewrites a source ruleset definition for the target environment: every source GUID becomes the
        matching target GUID (source GUID -> ref -> target GUID). Returns the rewritten JSON plus any
        GUIDs that could not be mapped, so the caller can fail loud instead of writing a broken ruleset.
    #>
    param(
        [string] $Definition,
        [hashtable] $SourceGuidToRef,
        [hashtable] $TargetKeyToGuid
    )
    if (-not $Definition) { return @{ Text = $Definition; Unmapped = @() } }

    $unmapped = [System.Collections.Generic.List[string]]::new()
    $text = $Definition
    foreach ($guid in (Get-CcGuids -Text $Definition)) {
        if ($SourceGuidToRef.ContainsKey($guid)) {
            $ref = $SourceGuidToRef[$guid]
            $composite = "$($ref.Entity)|$($ref.Key)"
            if ($TargetKeyToGuid.ContainsKey($composite)) {
                $text = $text.Replace($guid, $TargetKeyToGuid[$composite])
            }
            else {
                $unmapped.Add("$guid ($($ref.Entity): $($ref.Key))") | Out-Null
            }
        }
        # GUIDs unknown to source (system record types, option sets) are left untouched by design.
    }
    return @{ Text = $text; Unmapped = $unmapped }
}
