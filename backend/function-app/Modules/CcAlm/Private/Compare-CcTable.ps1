function Get-CcFormatted {
    # The value as Dataverse shows it (choice labels, Yes/No, dates), falling back to the raw value.
    param([pscustomobject] $Record, [string] $Column)
    if ($null -eq $Record) { return $null }
    $fv = $Record."$Column@OData.Community.Display.V1.FormattedValue"
    if ($null -ne $fv) { return [string]$fv }
    $v = $Record.$Column
    if ($null -eq $v) { return $null }
    if ($v -is [bool]) { if ($v) { return 'Yes' } else { return 'No' } }
    return [string]$v
}

function Test-CcSameValue {
    # Null and empty string are the same setting; everything else compares as invariant text.
    param($A, $B)
    $a = if ($null -eq $A) { '' } else { [string]$A }
    $b = if ($null -eq $B) { '' } else { [string]$B }
    return $a -ceq $b
}

function Get-CcDependencies {
    <#
    .SYNOPSIS
        The records one source record needs in the target before it can be written: every lookup to
        another moved table, every template it names by unique name, every record its definition
        embeds by GUID. Each carries the column it comes through and whether it is linked later.
    #>
    param([pscustomobject] $Record, [pscustomobject] $TablePlan, [pscustomobject] $Env, [hashtable] $Maps, [hashtable] $TablePlans)

    $deps = [System.Collections.Generic.List[object]]::new()
    $seen = @{}
    function Add-Dep($table, $key, $via, $deferred, $kind) {
        $id = "$table|$key"
        if ($seen.ContainsKey($id)) { return }
        $seen[$id] = $true
        $label = if ($key -like 'unresolved:*') { "a $(Get-CcItemLabel $TablePlans[$table].Table) that no longer exists" } else { Get-CcRefLabel $Maps $table $key $TablePlans }
        $deps.Add([pscustomobject]@{ table = $table; matchKey = $key; label = $label; via = $via; deferred = [bool]$deferred; kind = $kind }) | Out-Null
    }

    foreach ($lk in $TablePlan.Lookups) {
        $guid = ([string]$Record.($lk.ValueCol)).ToLowerInvariant()
        if (-not $guid) { continue }
        $ref = $Maps.SourceGuidToRef[$guid]
        if ($ref) { Add-Dep $ref.Entity $ref.Key $lk.Label $lk.Deferred 'lookup' }
        else { Add-Dep $lk.Target "unresolved:$guid" $lk.Label $lk.Deferred 'lookup' }
    }

    foreach ($tr in @($TablePlan.Table.textReferences)) {
        if (-not $tr) { continue }
        $targetPlan = $TablePlans[$tr.target]
        if (-not $targetPlan -or -not $targetPlan.Usable) { continue }
        foreach ($col in (Get-CcTextReferenceColumns -Reference $tr -Schema $TablePlan.SourceSchema)) {
            $v = [string]$Record.$col
            if (-not $v) { continue }
            $key = "$($tr.targetKey)=$($v.Trim().ToLowerInvariant())"
            $via = Get-CcColumnLabel $TablePlan $col
            if ($tr.label) { $via = if (([string]$tr.columns).EndsWith('*')) { "$($tr.label) ($($via.ToLowerInvariant()))" } else { $tr.label } }
            Add-Dep $tr.target $key $via $false 'name'
        }
    }

    foreach ($col in @($TablePlan.Table.guidBearingColumns)) {
        if (-not $col) { continue }
        $text = [string]$Record.$col
        foreach ($g in (Get-CcGuids -Text $text)) {
            $ref = $Maps.SourceGuidToRef[$g]
            if ($ref) { Add-Dep $ref.Entity $ref.Key (Get-CcColumnLabel $TablePlan $col) $false 'embedded' }
        }
    }
    return @($deps)
}

function Compare-CcTable {
    <#
    .SYNOPSIS
        Pairs one table's records across the two environments by key and classifies each:
        MissingInTarget, ExtraInTarget, Changed, Equal or Ambiguous. A Changed record lists each
        differing setting with its label and both values as a person reads them.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [pscustomobject] $TablePlan,
        [Parameter(Mandatory)] [pscustomobject] $Source,
        [Parameter(Mandatory)] [pscustomobject] $Target,
        [Parameter(Mandatory)] [hashtable] $Maps,
        [Parameter(Mandatory)] [hashtable] $TablePlans
    )

    $t = $TablePlan.Table
    $logical = $t.logicalName
    $records = [System.Collections.Generic.List[object]]::new()
    $srcByKey = $Source.ByKey[$logical]
    $tgtByKey = $Target.ByKey[$logical]

    function New-Row($status, $key, $srcRec, $tgtRec, $fields, $deps, $note) {
        $rec = if ($srcRec) { $srcRec } else { $tgtRec }
        $env = if ($srcRec) { $Source } else { $Target }
        [pscustomobject]@{
            matchKey    = $key
            status      = $status
            displayName = Get-CcRecordLabel -Record $rec -TablePlan $TablePlan
            context     = Get-CcRecordContext -Record $rec -TablePlan $TablePlan -Env $env -TablePlans $TablePlans
            # Filtered, not just @(): a function that returns nothing gives $null, and @($null) is a
            # one-element array - which once showed up as a phantom "needs a , which cannot be found".
            fields      = @($fields | Where-Object { $_ })
            dependsOn   = @($deps | Where-Object { $_ })
            note        = $note
        }
    }

    # What the duplicates have in common, for the Ambiguous message: "the same name and workstream".
    $keyLabels = @($t.matchKeys | ForEach-Object { (Get-CcColumnLabel $TablePlan $_).ToLowerInvariant() })
    $sameWhat = if ($keyLabels.Count -gt 1) { (($keyLabels[0..($keyLabels.Count - 2)]) -join ', ') + ' and ' + $keyLabels[-1] } else { $keyLabels[0] }
    $allLinks = @($t.matchKeys | Where-Object { $_ -notmatch '^_.*_value$' }).Count -eq 0
    function Get-DupNote($count, $where) {
        if ($allLinks) { return "The $where has $count identical links between the same records. Delete the extra one there." }
        return "$count records in the $where share the same $sameWhat, so they cannot be told apart. Rename or delete the extra one there."
    }

    foreach ($key in $srcByKey.Keys) {
        $srcIds = $srcByKey[$key]
        $srcRec = $Source.ById[$logical][$srcIds[0]]
        if ($srcRec.ismanaged -eq $true) { continue }   # ships with a managed solution in both orgs

        if ($srcIds.Count -gt 1) {
            $records.Add((New-Row 'Ambiguous' $key $srcRec $null @() @() (Get-DupNote $srcIds.Count 'source'))) | Out-Null
            continue
        }
        if ($tgtByKey.ContainsKey($key) -and $tgtByKey[$key].Count -gt 1) {
            $records.Add((New-Row 'Ambiguous' $key $srcRec $null @() @() (Get-DupNote $tgtByKey[$key].Count 'target'))) | Out-Null
            continue
        }

        $copies = if ($Source.Collapsed -and $Source.Collapsed[$logical]) { $Source.Collapsed[$logical][$key] } else { $null }
        $copyNote = if ($copies) { "The source has $copies identical copies of this record; they are moved as one." } else { $null }

        if (-not $tgtByKey.ContainsKey($key)) {
            $deps = Get-CcDependencies -Record $srcRec -TablePlan $TablePlan -Env $Source -Maps $Maps -TablePlans $TablePlans
            $records.Add((New-Row 'MissingInTarget' $key $srcRec $null @() $deps $copyNote)) | Out-Null
            continue
        }

        $tgtRec = $Target.ById[$logical][$tgtByKey[$key][0]]
        $fields = [System.Collections.Generic.List[object]]::new()

        foreach ($col in $TablePlan.DataColumns) {
            $isGuidBearing = @($t.guidBearingColumns) -contains $col
            if ($isGuidBearing) {
                $sN = ConvertTo-CcNormalisedDefinition -Definition ([string]$srcRec.$col) -GuidToRef $Maps.SourceGuidToRef
                $tN = ConvertTo-CcNormalisedDefinition -Definition ([string]$tgtRec.$col) -GuidToRef $Maps.TargetGuidToRef
                if (-not (Test-CcSameValue $sN.Text $tN.Text)) {
                    $added = @($sN.Refs | Where-Object { $tN.Refs -notcontains $_ })
                    $removed = @($tN.Refs | Where-Object { $sN.Refs -notcontains $_ })
                    $summary = @()
                    if ($added) { $summary += 'now also uses ' + (($added | ForEach-Object { $p = $_ -split '\|', 2; Get-CcRefLabel $Maps $p[0] $p[1] $TablePlans }) -join ', ') }
                    if ($removed) { $summary += 'no longer uses ' + (($removed | ForEach-Object { $p = $_ -split '\|', 2; Get-CcRefLabel $Maps $p[0] $p[1] $TablePlans }) -join ', ') }
                    if (-not $summary) { $summary = @('rule conditions or order differ') }
                    $fields.Add([pscustomobject]@{
                            name = $col; label = (Get-CcColumnLabel $TablePlan $col); kind = 'definition'
                            source = ($summary -join '; '); target = $null
                        }) | Out-Null
                }
                continue
            }
            if (-not (Test-CcSameValue $srcRec.$col $tgtRec.$col)) {
                $fields.Add([pscustomobject]@{
                        name = $col; label = (Get-CcColumnLabel $TablePlan $col); kind = 'value'
                        source = (Get-CcFormatted $srcRec $col); target = (Get-CcFormatted $tgtRec $col)
                    }) | Out-Null
            }
        }

        foreach ($lk in $TablePlan.Lookups) {
            $sg = ([string]$srcRec.($lk.ValueCol)).ToLowerInvariant()
            $tg = ([string]$tgtRec.($lk.ValueCol)).ToLowerInvariant()
            $sRef = if ($sg) { $Maps.SourceGuidToRef[$sg] } else { $null }
            $tRef = if ($tg) { $Maps.TargetGuidToRef[$tg] } else { $null }
            $sKey = if ($sRef) { "$($sRef.Entity)|$($sRef.Key)" } elseif ($sg) { "?$sg" } else { '' }
            $tKey = if ($tRef) { "$($tRef.Entity)|$($tRef.Key)" } elseif ($tg) { "?$tg" } else { '' }
            if ($sKey -ne $tKey) {
                $sText = if ($sRef) { (Get-CcRefLabel $Maps $sRef.Entity $sRef.Key $TablePlans) } elseif ($sg) { 'a record this tool does not move' } else { '(none)' }
                $tText = if ($tRef) { (Get-CcRefLabel $Maps $tRef.Entity $tRef.Key $TablePlans) } elseif ($tg) { 'a record this tool does not move' } else { '(none)' }
                $fields.Add([pscustomobject]@{ name = $lk.ValueCol; label = $lk.Label; kind = 'lookup'; source = $sText; target = $tText }) | Out-Null
            }
        }

        $status = if ($fields.Count -gt 0) { 'Changed' } else { 'Equal' }
        # Same records report their links too: "select a workstream with everything under it" walks
        # from the workstream through an unchanged routing configuration to a changed step.
        $deps = Get-CcDependencies -Record $srcRec -TablePlan $TablePlan -Env $Source -Maps $Maps -TablePlans $TablePlans
        $records.Add((New-Row $status $key $srcRec $tgtRec $fields $deps $copyNote)) | Out-Null
    }

    foreach ($key in $tgtByKey.Keys) {
        if ($srcByKey.ContainsKey($key)) { continue }
        $tgtRec = $Target.ById[$logical][$tgtByKey[$key][0]]
        if ($tgtRec.ismanaged -eq $true) { continue }
        $records.Add((New-Row 'ExtraInTarget' $key $null $tgtRec @() @() $null)) | Out-Null
    }

    return [pscustomobject]@{
        table   = $logical
        label   = Get-CcTableLabel $t
        group   = $t.group
        stage   = [int]$t.stage
        records = $records
        notes   = @()
    }
}
