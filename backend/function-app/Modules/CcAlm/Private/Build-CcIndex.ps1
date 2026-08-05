function Get-CcRecordId {
    param([pscustomobject] $Record, [pscustomobject] $Table)
    # Primary key column is the first select entry ending in 'id' matching the entity, or logicalName + 'id'.
    $pk = "$($Table.logicalName)id"
    if ($Record.PSObject.Properties.Name -contains $pk) { return [string]$Record.$pk }
    # ratingmodel/ratingvalue/characteristic follow the same rule; fall back to any *id at root.
    $cand = $Record.PSObject.Properties.Name | Where-Object { $_ -eq $pk }
    if ($cand) { return [string]$Record.$cand }
    return $null
}

function Get-CcNaturalKey {
    <#
    .SYNOPSIS
        Builds the natural key string for a record from the table's matchKeys.
        Lookup match keys (_x_value) are left as raw GUIDs here; callers that need cross-environment
        equality resolve those through the translation map first.
    #>
    param(
        [pscustomobject] $Record,
        [pscustomobject] $Table,
        [hashtable] $ResolvedLookups
    )

    $parts = foreach ($k in $Table.matchKeys) {
        $val = $null
        if ($ResolvedLookups -and $ResolvedLookups.ContainsKey($k)) {
            $val = $ResolvedLookups[$k]
        }
        elseif ($Record.PSObject.Properties.Name -contains $k) {
            $val = $Record.$k
        }
        "$k=$val"
    }
    return ($parts -join '|').ToLowerInvariant()
}

function Build-CcIndex {
    <#
    .SYNOPSIS
        For one table in one environment, returns:
          ById   : GUID -> record
          IdToKey: GUID -> natural key (lookups still raw at this stage)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object[]] $Records,
        [Parameter(Mandatory)] [pscustomobject] $Table
    )

    $byId    = @{}
    $idToKey = @{}

    foreach ($r in $Records) {
        $id = Get-CcRecordId -Record $r -Table $Table
        if (-not $id) { continue }
        $byId[$id] = $r
        $idToKey[$id] = Get-CcNaturalKey -Record $r -Table $Table
    }

    return [pscustomobject]@{
        Table   = $Table
        ById    = $byId
        IdToKey = $idToKey
    }
}
