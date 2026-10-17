# Natural keys: how "the same record" is recognised in two environments whose GUIDs differ.
#
# A key is built from the table's matchKeys. A matchKey that is a lookup (a routing step's parent
# configuration) is replaced by the parent's own key, recursively, so the key never contains an
# environment-specific GUID at any depth:
#
#   _msdyn_routingconfigurationid_value=[msdyn_name=contact center routing configuration|
#     _msdyn_liveworkstreamid_value=[msdyn_name=chat|msdyn_mode=717210000|msdyn_streamsource=192360000]]|
#   msdyn_name=route to queue
#
# Keys that collide inside one environment (two session templates both called "GovCase case
# session") take the table's tieBreaker column; if that still collides the records are Ambiguous
# and never paired at random.

function Get-CcRecordId {
    param([pscustomobject] $Record, [string] $PrimaryId)
    if ($Record.PSObject.Properties.Name -contains $PrimaryId) { return ([string]$Record.$PrimaryId).ToLowerInvariant() }
    return $null
}

function New-CcEnvData {
    <#
    .SYNOPSIS
        Indexes one environment's records for every table: by id, and (after Set-CcKeys) by key.
        Managed records stay in the index - children and lookups point at them - but are marked so
        compare and write leave them alone.
    #>
    param([string] $Side, [hashtable] $RecordsByTable, [hashtable] $TablePlans)
    $byId = @{}
    $guidToTable = @{}
    foreach ($logical in $RecordsByTable.Keys) {
        $plan = $TablePlans[$logical]
        $map = @{}
        foreach ($r in $RecordsByTable[$logical]) {
            $id = Get-CcRecordId -Record $r -PrimaryId $plan.PrimaryId
            if (-not $id) { continue }
            $map[$id] = $r
            $guidToTable[$id] = $logical
        }
        $byId[$logical] = $map
    }
    return [pscustomobject]@{
        Side        = $Side
        Records     = $RecordsByTable
        ById        = $byId
        GuidToTable = $guidToTable
        KeyById     = @{}
        ByKey       = @{}
        Ambiguous   = @{}
        # table -> key -> how many identical copies were taken as one record.
        Collapsed   = @{}
    }
}

function Get-CcKeyPart {
    param([pscustomobject] $Record, [string] $Column, [pscustomobject] $TablePlan, [pscustomobject] $Env)
    if ($Column -match '^_(.+)_value$') {
        $guid = ([string]$Record.$Column).ToLowerInvariant()
        if (-not $guid) { return "$Column=" }
        $lk = $TablePlan.Lookups | Where-Object ValueCol -eq $Column | Select-Object -First 1
        $refTable = if ($lk) { $lk.Target } else { $Env.GuidToTable[$guid] }
        if ($refTable -and $Env.KeyById[$refTable] -and $Env.KeyById[$refTable].ContainsKey($guid)) {
            return "$Column=[$($Env.KeyById[$refTable][$guid])]"
        }
        return "$Column=unresolved:$guid"
    }
    $v = $Record.$Column
    if ($null -eq $v) { $v = '' }
    return "$Column=$(([string]$v).Trim().ToLowerInvariant())"
}

function Set-CcKeys {
    <#
    .SYNOPSIS
        Computes every record's key in both environments, table by table in manifest order (parents
        first), applying the tie-breaker consistently on both sides so a duplicate in one org does
        not stop the other org's record from matching.
    #>
    param([pscustomobject] $Source, [pscustomobject] $Target, [object[]] $Tables, [hashtable] $TablePlans)

    foreach ($t in $Tables) {
        $plan = $TablePlans[$t.logicalName]
        if (-not $plan -or -not $plan.Usable) { continue }

        $base = @{}
        foreach ($env in $Source, $Target) {
            $m = @{}
            foreach ($id in $env.ById[$t.logicalName].Keys) {
                $r = $env.ById[$t.logicalName][$id]
                $m[$id] = (@($t.matchKeys | ForEach-Object { Get-CcKeyPart -Record $r -Column $_ -TablePlan $plan -Env $env }) -join '|')
            }
            $base[$env.Side] = $m
        }

        # Base keys that collide in either environment get the tie-breaker on both sides.
        $colliding = @{}
        foreach ($side in 'source', 'target') {
            $base[$side].Values | Group-Object | Where-Object Count -gt 1 | ForEach-Object { $colliding[$_.Name] = $true }
        }

        foreach ($env in $Source, $Target) {
            $keyById = @{}
            $byKey = @{}
            foreach ($id in $base[$env.Side].Keys) {
                $k = $base[$env.Side][$id]
                if ($colliding.ContainsKey($k) -and $t.tieBreaker) {
                    $tb = $env.ById[$t.logicalName][$id].($t.tieBreaker)
                    $k = "$k|#$($t.tieBreaker)=$(([string]$tb).Trim().ToLowerInvariant())"
                }
                $keyById[$id] = $k
                if (-not $byKey.ContainsKey($k)) { $byKey[$k] = [System.Collections.Generic.List[string]]::new() }
                $byKey[$k].Add($id) | Out-Null
            }
            # Copies that are the same in every setting (a quick reply created three times) cannot be
            # told apart and need not be: they are one record. The first stands for all of them, and
            # links from any copy resolve to it through the shared key.
            $env.Collapsed[$t.logicalName] = @{}
            foreach ($k in @($byKey.Keys)) {
                if ($byKey[$k].Count -lt 2) { continue }
                $ids = @($byKey[$k] | Sort-Object)
                if (Test-CcIdenticalRecords -Records @($ids | ForEach-Object { $env.ById[$t.logicalName][$_] }) -TablePlan $plan) {
                    $env.Collapsed[$t.logicalName][$k] = $ids.Count
                    $byKey[$k] = [System.Collections.Generic.List[string]]::new()
                    $byKey[$k].Add($ids[0]) | Out-Null
                }
            }
            $env.KeyById[$t.logicalName] = $keyById
            $env.ByKey[$t.logicalName] = $byKey
            $env.Ambiguous[$t.logicalName] = @{}
            foreach ($k in $byKey.Keys) { if ($byKey[$k].Count -gt 1) { $env.Ambiguous[$t.logicalName][$k] = $true } }
        }
    }
}

function Test-CcIdenticalRecords {
    # True when every record has the same value in every compared setting and lookup.
    param([object[]] $Records, [pscustomobject] $TablePlan)
    $first = $Records[0]
    foreach ($r in $Records | Select-Object -Skip 1) {
        foreach ($col in $TablePlan.DataColumns) { if (-not (Test-CcSameValue $first.$col $r.$col)) { return $false } }
        foreach ($lk in $TablePlan.Lookups) {
            if (([string]$first.($lk.ValueCol)).ToLowerInvariant() -ne ([string]$r.($lk.ValueCol)).ToLowerInvariant()) { return $false }
        }
    }
    return $true
}

function Get-CcRecordByKey {
    # The single record with this key, or $null when there is none or it is ambiguous.
    param([pscustomobject] $Env, [string] $Table, [string] $Key)
    $ids = $Env.ByKey[$Table]
    if (-not $ids -or -not $ids.ContainsKey($Key) -or $ids[$Key].Count -ne 1) { return $null }
    return $Env.ById[$Table][$ids[$Key][0]]
}

function Get-CcIdByKey {
    param([pscustomobject] $Env, [string] $Table, [string] $Key)
    $ids = $Env.ByKey[$Table]
    if (-not $ids -or -not $ids.ContainsKey($Key) -or $ids[$Key].Count -ne 1) { return $null }
    return $ids[$Key][0]
}

function Get-CcRecordLabel {
    <#
    .SYNOPSIS
        What a person calls this record: the table's display template, else its primary name, else
        the first readable match key value. Never a GUID or a raw key.
    #>
    param([pscustomobject] $Record, [pscustomobject] $TablePlan)
    $t = $TablePlan.Table
    if ($t.displayTemplate) {
        $evaluator = [System.Text.RegularExpressions.MatchEvaluator]{
            param($m)
            $col = $m.Groups[1].Value
            $fv = $Record."$col@OData.Community.Display.V1.FormattedValue"
            if ($fv) { return [string]$fv }
            if ($Record.PSObject.Properties.Name -contains $col -and $null -ne $Record.$col) { return [string]$Record.$col }
            return ''
        }
        $label = ([regex]::Replace($t.displayTemplate, '\{(\w+)\}', $evaluator)).Trim()
        if ($label) { return $label }
    }
    $nameCol = if ($t.displayColumn) { $t.displayColumn } else { $TablePlan.PrimaryName }
    if ($nameCol -and $Record.$nameCol) { return [string]$Record.$nameCol }
    foreach ($k in $t.matchKeys) {
        if ($k -notmatch '^_.*_value$' -and $Record.$k) { return [string]$Record.$k }
    }
    return '(unnamed)'
}

function Get-CcRecordContext {
    <#
    .SYNOPSIS
        Where a record lives, for tables matched under a parent: "Chat › Contact center routing
        configuration" for a routing step. Empty for free-standing records.
    #>
    param([pscustomobject] $Record, [pscustomobject] $TablePlan, [pscustomobject] $Env, [hashtable] $TablePlans, [int] $Depth = 0)
    if ($Depth -gt 3) { return '' }
    foreach ($k in $TablePlan.Table.matchKeys) {
        if ($k -notmatch '^_.*_value$') { continue }
        $guid = ([string]$Record.$k).ToLowerInvariant()
        if (-not $guid) { continue }
        $lk = $TablePlan.Lookups | Where-Object ValueCol -eq $k | Select-Object -First 1
        if (-not $lk) { continue }
        $parent = $Env.ById[$lk.Target][$guid]
        if (-not $parent) { continue }
        $parentPlan = $TablePlans[$lk.Target]
        $parentLabel = Get-CcRecordLabel -Record $parent -TablePlan $parentPlan
        $grand = Get-CcRecordContext -Record $parent -TablePlan $parentPlan -Env $Env -TablePlans $TablePlans -Depth ($Depth + 1)
        if ($grand) { return "$grand › $parentLabel" }
        return $parentLabel
    }
    return ''
}

function Build-CcMaps {
    <#
    .SYNOPSIS
        The lookup tables that cross the two environments:
          SourceGuidToRef / TargetGuidToRef : guid -> @{ Entity; Key }
          TargetKeyToGuid                   : "entity|key" -> target guid (unambiguous keys only)
          Labels                            : "entity|key" -> @{ DisplayName; Context }
    #>
    param([pscustomobject] $Source, [pscustomobject] $Target, [hashtable] $TablePlans)
    $srcRef = @{}; $tgtRef = @{}; $tgtKeyToGuid = @{}; $labels = @{}
    foreach ($pair in @(@{ Env = $Source; Ref = $srcRef }, @{ Env = $Target; Ref = $tgtRef })) {
        $env = $pair.Env
        foreach ($logical in $env.KeyById.Keys) {
            $plan = $TablePlans[$logical]
            foreach ($id in $env.KeyById[$logical].Keys) {
                $key = $env.KeyById[$logical][$id]
                $pair.Ref[$id] = @{ Entity = $logical; Key = $key }
                $refKey = "$logical|$key"
                if (-not $labels.ContainsKey($refKey) -or $env.Side -eq 'source') {
                    $rec = $env.ById[$logical][$id]
                    $labels[$refKey] = @{
                        DisplayName = Get-CcRecordLabel -Record $rec -TablePlan $plan
                        Context     = Get-CcRecordContext -Record $rec -TablePlan $plan -Env $env -TablePlans $TablePlans
                    }
                }
                if ($env.Side -eq 'target' -and $env.ByKey[$logical][$key].Count -eq 1) { $tgtKeyToGuid[$refKey] = $id }
            }
        }
    }
    return @{ SourceGuidToRef = $srcRef; TargetGuidToRef = $tgtRef; TargetKeyToGuid = $tgtKeyToGuid; Labels = $labels }
}

function Get-CcItemLabel {
    # The singular, lower-case noun for one record of a table: "workstream", "routing step".
    param($Table)
    if ($Table.item) { return $Table.item }
    return (Get-CcTableLabel $Table).ToLowerInvariant()
}

function Get-CcRefLabel {
    # "routing configuration 'Chat › Contact center routing configuration'" for messages.
    param([hashtable] $Maps, [string] $Entity, [string] $Key, [hashtable] $TablePlans)
    $l = $Maps.Labels["$Entity|$Key"]
    $item = if ($TablePlans -and $TablePlans[$Entity]) { Get-CcItemLabel $TablePlans[$Entity].Table } else { $Entity }
    if (-not $l) { return "a $item" }
    $name = if ($l.Context) { "$($l.Context) › $($l.DisplayName)" } else { $l.DisplayName }
    return "$item '$name'"
}
