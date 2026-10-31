# Record routing intake rules. Every table with record routing (Case routing hub for incident) has
# one intake ruleset, and each rule in it sends the records it matches to one workstream. That
# ruleset is shared by all of the table's workstreams and often comes with a managed solution, so
# it is not moved as a whole: its rules are compared one by one ("Intake rules"), each sits under
# the workstream it routes to and is ticked with it, and a run merges the selected rules into the
# target's own intake ruleset. The target's other rules stay as they are, in their order.

$script:CcIntakeTable = 'intakerule'
$script:CcHubTable = 'msdyn_masterentityroutingconfiguration'
$script:CcRulesetTable = 'msdyn_decisionruleset'

function Get-CcIntakeRulesets {
    # Hub key -> its intake ruleset in one environment: @{ HubId; HubKey; RulesetId; Definition; Rules }.
    param([pscustomobject] $Env)
    $out = @{}
    $hubs = $Env.ById[$script:CcHubTable]
    if (-not $hubs) { return $out }
    foreach ($id in $hubs.Keys) {
        $key = $Env.KeyById[$script:CcHubTable][$id]
        if (-not $key -or $Env.ByKey[$script:CcHubTable][$key].Count -ne 1) { continue }
        $rsId = ([string]$hubs[$id]._msdyn_rulesetid_value).ToLowerInvariant()
        $rs = if ($rsId -and $Env.ById[$script:CcRulesetTable]) { $Env.ById[$script:CcRulesetTable][$rsId] } else { $null }
        $def = if ($rs) { [string]$rs.msdyn_rulesetdefinition } else { $null }
        $out[$key] = [pscustomobject]@{
            HubId      = $id
            HubKey     = $key
            RulesetId  = $(if ($rs) { $rsId } else { $null })
            Definition = $def
            Rules      = @(Get-CcIntakeRuleList -Definition $def)
        }
    }
    return $out
}

function Get-CcIntakeRuleKey {
    # A rule is known by its name, as the admin center shows it; the id differs per environment.
    param([System.Xml.XmlElement] $Rule)
    $name = $Rule.GetAttribute('name')
    if (-not $name.Trim()) { return "id=$($Rule.GetAttribute('id').ToLowerInvariant())" }
    return "name=$($name.Trim().ToLowerInvariant())"
}

function Get-CcIntakeRuleList {
    # The rules of an intake ruleset's definition, in order: @{ Key; Name; Xml }. The id is left out
    # of Xml, so two environments' copies of a rule compare on what it does.
    param([string] $Definition)
    if (-not $Definition) { return @() }
    $doc = [System.Xml.XmlDocument]::new()
    try { $doc.LoadXml($Definition) } catch { return @() }
    return @($doc.SelectNodes('//rules/rule') | ForEach-Object {
            $c = $_.CloneNode($true)
            [void]$c.Attributes.RemoveNamedItem('id')
            [pscustomobject]@{ Key = (Get-CcIntakeRuleKey $_); Name = $_.GetAttribute('name').Trim(); Xml = $c.OuterXml }
        })
}

function New-CcIntakeTablePlan {
    # A table plan for the rules, so plan and run treat them like any other table: written after the
    # workstreams they route to exist, into the target's ruleset.
    param([hashtable] $SourceSets, [hashtable] $TargetSets, [pscustomobject] $RulesetPlan)
    [pscustomobject]@{
        Table            = [pscustomobject]@{ logicalName = $script:CcIntakeTable; label = 'Intake rules'; item = 'intake rule'; group = 'Workstreams'; stage = 98; order = 98; move = 'intake'; matchKeys = @('rule') }
        Usable           = $true
        Intake           = [pscustomobject]@{ Source = $SourceSets; Target = $TargetSets }
        LogicalName      = $script:CcIntakeTable
        EntitySet        = $RulesetPlan.EntitySet
        Lookups          = @()
        DataColumns      = @()
        RequiredExternal = @()
        MissingInTarget  = @()
        TargetSchema     = [pscustomobject]@{ Attributes = @{} }
        SourceSchema     = [pscustomobject]@{ Attributes = @{} }
    }
}

function Get-CcIntakeRulesetKeys {
    # "table|key" of every intake ruleset in either environment, which the ruleset table leaves out.
    param([hashtable] $SourceSets, [hashtable] $TargetSets, [pscustomobject] $Source, [pscustomobject] $Target)
    $keys = @{}
    foreach ($pair in @(@{ Sets = $SourceSets; Env = $Source }, @{ Sets = $TargetSets; Env = $Target })) {
        foreach ($s in $pair.Sets.Values) {
            if ($s.RulesetId) { $keys["$($script:CcRulesetTable)|$($pair.Env.KeyById[$script:CcRulesetTable][$s.RulesetId])"] = $true }
        }
    }
    return $keys
}

function Compare-CcIntakeRules {
    <#
    .SYNOPSIS
        Every hub's intake rules in both environments, paired by hub and rule name. A rule sits under
        the workstream it routes to; it also needs its hub, which the target must have.
    #>
    param([hashtable] $SourceSets, [hashtable] $TargetSets, [hashtable] $Maps, [hashtable] $TablePlans)

    $records = [System.Collections.Generic.List[object]]::new()
    $hubKeys = @(@($SourceSets.Keys) + @($TargetSets.Keys) | Select-Object -Unique)
    foreach ($hubKey in $hubKeys) {
        $hubLabel = $Maps.Labels["$($script:CcHubTable)|$hubKey"].DisplayName
        $src = if ($SourceSets[$hubKey]) { @($SourceSets[$hubKey].Rules) } else { @() }
        $tgt = if ($TargetSets[$hubKey]) { @($TargetSets[$hubKey].Rules) } else { @() }
        $srcCount = @{}; foreach ($r in $src) { $srcCount[$r.Key] = 1 + [int]$srcCount[$r.Key] }
        $tgtByKey = @{}; foreach ($r in $tgt) { if (-not $tgtByKey.ContainsKey($r.Key)) { $tgtByKey[$r.Key] = [System.Collections.Generic.List[object]]::new() }; $tgtByKey[$r.Key].Add($r) | Out-Null }

        function New-RuleRow($status, $rule, $fields, $deps, $note) {
            $key = "$hubKey|$($rule.Key)"
            $Maps.Labels["$($script:CcIntakeTable)|$key"] = @{ DisplayName = $rule.Name; Context = $hubLabel }
            [pscustomobject]@{ matchKey = $key; status = $status; displayName = $rule.Name; context = $hubLabel; fields = @($fields); dependsOn = @($deps); note = $note }
        }

        $seen = @{}
        foreach ($rule in $src) {
            if ($seen.ContainsKey($rule.Key)) { continue }
            $seen[$rule.Key] = $true
            if ($srcCount[$rule.Key] -gt 1 -or ($tgtByKey.ContainsKey($rule.Key) -and $tgtByKey[$rule.Key].Count -gt 1)) {
                $where = if ($srcCount[$rule.Key] -gt 1) { 'source' } else { 'target' }
                $n = if ($where -eq 'source') { $srcCount[$rule.Key] } else { $tgtByKey[$rule.Key].Count }
                $records.Add((New-RuleRow 'Ambiguous' $rule @() @() "$n intake rules of $hubLabel in the $where have the same name, so they cannot be told apart. Rename one there.")) | Out-Null
                continue
            }
            $deps = Get-CcIntakeRuleDependencies -Rule $rule -HubKey $hubKey -Maps $Maps -TablePlans $TablePlans
            if (-not $tgtByKey.ContainsKey($rule.Key)) {
                $records.Add((New-RuleRow 'MissingInTarget' $rule @() $deps $null)) | Out-Null
                continue
            }
            $sN = ConvertTo-CcNormalisedDefinition -Definition $rule.Xml -GuidToRef $Maps.SourceGuidToRef
            $tN = ConvertTo-CcNormalisedDefinition -Definition $tgtByKey[$rule.Key][0].Xml -GuidToRef $Maps.TargetGuidToRef
            if (Test-CcSameValue $sN.Text $tN.Text) {
                $records.Add((New-RuleRow 'Equal' $rule @() $deps $null)) | Out-Null
                continue
            }
            $added = @($sN.Refs | Where-Object { $tN.Refs -notcontains $_ })
            $removed = @($tN.Refs | Where-Object { $sN.Refs -notcontains $_ })
            $summary = @()
            if ($added) { $summary += 'now routes to ' + (($added | ForEach-Object { $p = $_ -split '\|', 2; Get-CcRefLabel $Maps $p[0] $p[1] $TablePlans }) -join ', ') }
            if ($removed) { $summary += 'no longer routes to ' + (($removed | ForEach-Object { $p = $_ -split '\|', 2; Get-CcRefLabel $Maps $p[0] $p[1] $TablePlans }) -join ', ') }
            if (-not $summary) { $summary = @('rule conditions differ') }
            $field = [pscustomobject]@{ name = 'rule'; label = 'Rule'; kind = 'definition'; source = ($summary -join '; '); target = $null }
            $records.Add((New-RuleRow 'Changed' $rule @($field) $deps $null)) | Out-Null
        }
        foreach ($rule in $tgt) {
            if ($seen.ContainsKey($rule.Key)) { continue }
            $seen[$rule.Key] = $true
            $records.Add((New-RuleRow 'ExtraInTarget' $rule @() @() $null)) | Out-Null
        }
    }

    return [pscustomobject]@{
        table   = $script:CcIntakeTable
        label   = 'Intake rules'
        group   = 'Workstreams'
        stage   = 98
        records = $records
        notes   = @()
    }
}

function Get-CcIntakeRuleDependencies {
    # The workstream a rule routes to first (where it sits), then its hub, then anything else its
    # conditions name by GUID.
    param([pscustomobject] $Rule, [string] $HubKey, [hashtable] $Maps, [hashtable] $TablePlans)
    $refs = @(Get-CcGuids -Text $Rule.Xml | ForEach-Object { $Maps.SourceGuidToRef[$_] } | Where-Object { $_ })
    $deps = [System.Collections.Generic.List[object]]::new()
    $seen = @{}
    $ordered = @($refs | Where-Object { $_.Entity -eq 'msdyn_liveworkstream' }) + @(@{ Entity = $script:CcHubTable; Key = $HubKey }) + @($refs | Where-Object { $_.Entity -ne 'msdyn_liveworkstream' })
    foreach ($r in $ordered) {
        $id = "$($r.Entity)|$($r.Key)"
        if ($seen.ContainsKey($id)) { continue }
        $seen[$id] = $true
        $kind = if ($r.Entity -in 'msdyn_liveworkstream', $script:CcHubTable) { 'lookup' } else { 'embedded' }
        $via = if ($r.Entity -eq $script:CcHubTable) { 'Record routing hub' } else { 'Intake rule' }
        $deps.Add([pscustomobject]@{ table = $r.Entity; matchKey = $r.Key; label = (Get-CcRefLabel $Maps $r.Entity $r.Key $TablePlans); via = $via; deferred = $false; kind = $kind }) | Out-Null
    }
    return @($deps)
}

function Merge-CcIntakeRule {
    <#
    .SYNOPSIS
        The target's intake ruleset definition with one rule from the source put in: in place of the
        target's rule of the same name (keeping its id), else straight after the nearest rule that
        comes before it in the source, else first. The first rule that matches a record wins, so
        where it goes matters.
    #>
    param([string] $TargetDefinition, [string] $RuleXml, [string] $RuleKey, [string[]] $SourceOrder)
    $doc = [System.Xml.XmlDocument]::new()
    $doc.PreserveWhitespace = $true
    $doc.LoadXml($TargetDefinition)
    $rulesNode = $doc.SelectSingleNode('//rules')
    if (-not $rulesNode) { throw 'The target intake ruleset has no rules element.' }
    $frag = [System.Xml.XmlDocument]::new()
    $frag.LoadXml($RuleXml)
    $new = $doc.ImportNode($frag.DocumentElement, $true)

    $existing = @($rulesNode.SelectNodes('rule'))
    $byKey = @{}
    foreach ($r in $existing) { if (-not $byKey.ContainsKey((Get-CcIntakeRuleKey $r))) { $byKey[(Get-CcIntakeRuleKey $r)] = $r } }
    if ($byKey.ContainsKey($RuleKey)) {
        $old = $byKey[$RuleKey]
        $new.SetAttribute('id', $old.GetAttribute('id'))
        [void]$rulesNode.ReplaceChild($new, $old)
        return $doc.OuterXml
    }
    $new.SetAttribute('id', [guid]::NewGuid().ToString())
    $at = [array]::IndexOf($SourceOrder, $RuleKey)
    for ($j = $at - 1; $j -ge 0; $j--) {
        if ($byKey.ContainsKey($SourceOrder[$j])) {
            [void]$rulesNode.InsertAfter($new, $byKey[$SourceOrder[$j]])
            return $doc.OuterXml
        }
    }
    if ($existing.Count -gt 0) { [void]$rulesNode.InsertBefore($new, $existing[0]) }
    else { [void]$rulesNode.AppendChild($new) }
    return $doc.OuterXml
}

function Get-CcIntakeSourceRule {
    # The source rule an operation writes, with its GUIDs rewritten for the target.
    param([pscustomobject] $TablePlan, [string] $MatchKey, [hashtable] $Maps, [hashtable] $TablePlans)
    $hubKey, $ruleKey = $MatchKey -split '\|(?=(?:name|id)=)', 2
    $set = $TablePlan.Intake.Source[$hubKey]
    $rule = if ($set) { @($set.Rules | Where-Object Key -eq $ruleKey) | Select-Object -First 1 } else { $null }
    if (-not $rule) { return [pscustomobject]@{ HubKey = $hubKey; RuleKey = $ruleKey; Xml = $null; Order = @(); Problem = 'The source rule could not be found any more. Compare again.' } }
    $rw =ConvertTo-CcTargetDefinition -Definition $rule.Xml -SourceGuidToRef $Maps.SourceGuidToRef -TargetKeyToGuid $Maps.TargetKeyToGuid
    $problem = $null
    if ($rw.Unmapped.Count -gt 0) {
        $names = @($rw.Unmapped | ForEach-Object { Get-CcRefLabel $Maps $_.Entity $_.Key $TablePlans }) | Select-Object -Unique
        $problem = "It routes to or names $($names -join ', '), not in the target."
    }
    return [pscustomobject]@{ HubKey = $hubKey; RuleKey = $ruleKey; Xml = $rw.Text; Order = @($set.Rules | ForEach-Object Key); Problem = $problem }
}
