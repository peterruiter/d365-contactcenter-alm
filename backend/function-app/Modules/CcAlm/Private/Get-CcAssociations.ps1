# Many-to-many links between moved tables: a quick reply on several workstreams, a tag on a quick
# reply. They are not columns of either record, so they are read from the relationship's intersect
# table, compared as records of their own ("Quick replies on workstreams"), and written after both
# ends exist by associating the two records.
#
# The relationships come from each org's metadata, like everything else: every many-to-many
# relationship between two manifest tables that both orgs have. The end written first (the lower
# manifest order) owns the link: ticking a workstream brings its quick-reply links and, through
# them, the quick replies; ticking a quick reply does not drag in every workstream it is on.

function Get-CcAssociationPlans {
    param([pscustomobject] $Manifest, [hashtable] $TablePlans, [pscustomobject] $Source, [pscustomobject] $Target)
    $byLogical = @{}
    foreach ($t in $Manifest.tables) { $byLogical[$t.logicalName] = $t }
    $defs = [ordered]@{}
    foreach ($t in $Manifest.tables) {
        $plan = $TablePlans[$t.logicalName]
        if (-not $plan -or -not $plan.Usable -or $t.move -in 'reference', 'detect') { continue }
        foreach ($m in @($plan.SourceSchema.ManyToMany)) {
            if (-not $m -or $defs.Contains($m.SchemaName)) { continue }
            $e1 = $m.Entity1LogicalName; $e2 = $m.Entity2LogicalName
            if ($e1 -eq $e2) { continue }
            $p1 = $TablePlans[$e1]; $p2 = $TablePlans[$e2]
            if (-not $p1 -or -not $p2 -or -not $p1.Usable -or -not $p2.Usable) { continue }
            if ($byLogical[$e1].move -in 'reference', 'detect' -or $byLogical[$e2].move -in 'reference', 'detect') { continue }
            # The target must have the same relationship.
            $inTarget = @($p1.TargetSchema.ManyToMany) + @($p2.TargetSchema.ManyToMany) | Where-Object { $_ -and $_.SchemaName -eq $m.SchemaName } | Select-Object -First 1
            if (-not $inTarget) { continue }
            $si = Get-CcTableSchema -Environment $Source -LogicalName $m.IntersectEntityName
            $ti = Get-CcTableSchema -Environment $Target -LogicalName $m.IntersectEntityName
            if (-not $si.Exists -or -not $ti.Exists) { continue }

            $owner = if ([int]$byLogical[$e1].order -le [int]$byLogical[$e2].order) { $e1 } else { $e2 }
            $other = if ($owner -eq $e1) { $e2 } else { $e1 }
            $ownerLabel = Get-CcTableLabel $byLogical[$owner]
            $defs[$m.SchemaName] = [pscustomobject]@{
                SchemaName      = $m.SchemaName
                Entity1         = $e1
                Entity2         = $e2
                Attr1           = $m.Entity1IntersectAttribute
                Attr2           = $m.Entity2IntersectAttribute
                Nav1            = $m.Entity1NavigationPropertyName
                SourceSet       = $si.EntitySet
                TargetSet       = $ti.EntitySet
                Owner           = $owner
                Other           = $other
                Label           = "$(Get-CcTableLabel $byLogical[$other]) on $($ownerLabel.Substring(0, 1).ToLowerInvariant() + $ownerLabel.Substring(1))"
                Group           = $byLogical[$owner].group
            }
        }
    }
    return @($defs.Values)
}

function New-CcAssociationTablePlan {
    # A table plan for the links, so plan and run treat them like any other table: written in the
    # final stage, after both ends exist.
    param([pscustomobject] $Def)
    [pscustomobject]@{
        Table            = [pscustomobject]@{ logicalName = $Def.SchemaName; label = $Def.Label; item = 'link'; group = $Def.Group; stage = 99; order = 99; move = 'associate'; matchKeys = @('link') }
        Usable           = $true
        Association      = $Def
        LogicalName      = $Def.SchemaName
        Lookups          = @()
        DataColumns      = @()
        RequiredExternal = @()
        MissingInTarget  = @()
        TargetSchema     = [pscustomobject]@{ Attributes = @{} }
        SourceSchema     = [pscustomobject]@{ Attributes = @{} }
    }
}

function Read-CcAssociationPairs {
    param([pscustomobject] $Environment, [string] $EntitySet, [pscustomobject] $Def)
    $rows = @(Get-CcRecords -Environment $Environment -EntitySet $EntitySet -Select @($Def.Attr1, $Def.Attr2))
    return @($rows | ForEach-Object {
            $a = [string]$_.($Def.Attr1); $b = [string]$_.($Def.Attr2)
            if ($a -and $b) { [pscustomobject]@{ Id1 = $a.ToLowerInvariant(); Id2 = $b.ToLowerInvariant() } }
        })
}

function Compare-CcAssociations {
    <#
    .SYNOPSIS
        One relationship's links in both environments, paired by what their two ends are. A link whose
        ends this tool cannot identify (a managed record, a personal queue) is left out.
    #>
    param([pscustomobject] $Def, [object[]] $SourcePairs, [object[]] $TargetPairs, [hashtable] $Maps, [hashtable] $TablePlans, [pscustomobject] $Source, [pscustomobject] $Target)

    function Get-Link($pair, $guidToRef) {
        $r1 = $guidToRef[$pair.Id1]; $r2 = $guidToRef[$pair.Id2]
        if (-not $r1 -or -not $r2) { return $null }
        $ownerRef = if ($Def.Owner -eq $Def.Entity1) { $r1 } else { $r2 }
        $otherRef = if ($Def.Owner -eq $Def.Entity1) { $r2 } else { $r1 }
        [pscustomobject]@{ Key = "$($ownerRef.Entity)|$($ownerRef.Key) <> $($otherRef.Entity)|$($otherRef.Key)"; Owner = $ownerRef; Other = $otherRef }
    }

    $src = @{}; foreach ($p in @($SourcePairs | Where-Object { $_ })) { $l = Get-Link $p $Maps.SourceGuidToRef; if ($l) { $src[$l.Key] = $l } }
    $tgt = @{}; foreach ($p in @($TargetPairs | Where-Object { $_ })) { $l = Get-Link $p $Maps.TargetGuidToRef; if ($l) { $tgt[$l.Key] = $l } }

    $records = [System.Collections.Generic.List[object]]::new()
    function New-LinkRow($status, $link) {
        $owner = $Maps.Labels["$($link.Owner.Entity)|$($link.Owner.Key)"]
        $other = $Maps.Labels["$($link.Other.Entity)|$($link.Other.Key)"]
        $ownerName = if ($owner.Context) { "$($owner.Context) › $($owner.DisplayName)" } else { $owner.DisplayName }
        $otherName = if ($other.Context) { "$($other.Context) › $($other.DisplayName)" } else { $other.DisplayName }
        [pscustomobject]@{
            matchKey    = $link.Key
            status      = $status
            displayName = $otherName
            context     = $ownerName
            fields      = @()
            # The owner as a parent (it brings the link); the other end as something the link uses.
            dependsOn   = @(
                [pscustomobject]@{ table = $link.Owner.Entity; matchKey = $link.Owner.Key; label = (Get-CcRefLabel $Maps $link.Owner.Entity $link.Owner.Key $TablePlans); via = $Def.Label; deferred = $false; kind = 'lookup' }
                [pscustomobject]@{ table = $link.Other.Entity; matchKey = $link.Other.Key; label = (Get-CcRefLabel $Maps $link.Other.Entity $link.Other.Key $TablePlans); via = $Def.Label; deferred = $true; kind = 'lookup' }
            )
            note        = $null
        }
    }
    foreach ($k in $src.Keys) { $records.Add((New-LinkRow $(if ($tgt.ContainsKey($k)) { 'Equal' } else { 'MissingInTarget' }) $src[$k])) | Out-Null }
    foreach ($k in $tgt.Keys) { if (-not $src.ContainsKey($k)) { $records.Add((New-LinkRow 'ExtraInTarget' $tgt[$k])) | Out-Null } }

    return [pscustomobject]@{
        table   = $Def.SchemaName
        label   = $Def.Label
        group   = $Def.Group
        stage   = 99
        records = $records
        notes   = @()
    }
}
