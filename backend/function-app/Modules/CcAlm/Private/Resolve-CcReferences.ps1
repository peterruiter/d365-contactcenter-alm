# GUIDs embedded in text (a ruleset definition naming the queues it routes to). Compared by what
# they point at, and rewritten to the target's GUIDs on write.

$script:CcGuidPattern = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'

function Get-CcGuids {
    param([string] $Text)
    if (-not $Text) { return @() }
    return @([regex]::Matches($Text, $script:CcGuidPattern) | ForEach-Object { $_.Value.ToLowerInvariant() } | Select-Object -Unique)
}

function Convert-CcGuidsInText {
    # Replaces every GUID the map knows, matching case-insensitively: definitions are not
    # consistent about upper or lower case, and a missed match silently keeps a source GUID.
    param([string] $Text, [scriptblock] $Replace)
    return [regex]::Replace($Text, $script:CcGuidPattern, [System.Text.RegularExpressions.MatchEvaluator]{
            param($m)
            $r = & $Replace $m.Value.ToLowerInvariant()
            if ($null -eq $r) { return $m.Value }
            return $r
        })
}

function ConvertTo-CcNormalisedDefinition {
    <#
    .SYNOPSIS
        Replaces each embedded GUID with {entity:key} so two environments' definitions compare on
        content. Each side normalises with ITS OWN map. Unknown GUIDs (system record types, option
        sets) stay as they are, which is right: those are the same value everywhere.
    #>
    param([string] $Definition, [hashtable] $GuidToRef)
    if (-not $Definition) { return @{ Text = $Definition; Refs = @() } }
    $refs = [System.Collections.Generic.List[string]]::new()
    $text = Convert-CcGuidsInText -Text $Definition -Replace {
        param($g)
        if ($GuidToRef.ContainsKey($g)) {
            $ref = $GuidToRef[$g]
            $refs.Add("$($ref.Entity)|$($ref.Key)") | Out-Null
            return "{$($ref.Entity):$($ref.Key)}"
        }
        return $null
    }
    return @{ Text = $text; Refs = @($refs | Select-Object -Unique) }
}

function ConvertTo-CcTargetDefinition {
    <#
    .SYNOPSIS
        Rewrites a source definition for the target: source GUID -> what it points at -> that
        record's GUID in target. Returns the GUIDs it could not map, so the caller blocks the write
        instead of saving a ruleset that points at nothing.
    #>
    param([string] $Definition, [hashtable] $SourceGuidToRef, [hashtable] $TargetKeyToGuid)
    if (-not $Definition) { return @{ Text = $Definition; Unmapped = @() } }
    $unmapped = [System.Collections.Generic.List[object]]::new()
    $text = Convert-CcGuidsInText -Text $Definition -Replace {
        param($g)
        if (-not $SourceGuidToRef.ContainsKey($g)) { return $null }
        $ref = $SourceGuidToRef[$g]
        $composite = "$($ref.Entity)|$($ref.Key)"
        if ($TargetKeyToGuid.ContainsKey($composite)) { return $TargetKeyToGuid[$composite] }
        $unmapped.Add(@{ Entity = $ref.Entity; Key = $ref.Key; Guid = $g }) | Out-Null
        return $null
    }
    return @{ Text = $text; Unmapped = @($unmapped) }
}
