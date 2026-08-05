function Build-CcGlobalMaps {
    <#
    .SYNOPSIS
        Builds the maps that drive cross-environment matching and GUID remapping.
          SourceGuidToRef : sourceGuid -> @{ Entity; Key }
          TargetKeyToGuid : "entity|naturalKey" -> targetGuid
        Indexes is a hashtable of logicalName -> index object from Build-CcIndex, one set per environment.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [hashtable] $SourceIndexes,
        [Parameter(Mandatory)] [hashtable] $TargetIndexes
    )

    $sourceGuidToRef = @{}
    foreach ($logical in $SourceIndexes.Keys) {
        $idx = $SourceIndexes[$logical]
        foreach ($guid in $idx.IdToKey.Keys) {
            $sourceGuidToRef[$guid] = @{ Entity = $logical; Key = $idx.IdToKey[$guid] }
        }
    }

    $targetKeyToGuid = @{}
    foreach ($logical in $TargetIndexes.Keys) {
        $idx = $TargetIndexes[$logical]
        foreach ($guid in $idx.IdToKey.Keys) {
            $composite = "$logical|$($idx.IdToKey[$guid])"
            $targetKeyToGuid[$composite] = $guid
        }
    }

    return [pscustomobject]@{
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
