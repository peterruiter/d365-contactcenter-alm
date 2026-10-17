function Get-CcErrorMessage {
    <#
    .SYNOPSIS
        The sentence a person needs from a failed Web API call: Dataverse's own error message, without
        the URL, status line and JSON wrapping around it.
    #>
    param([string] $Text)
    if (-not $Text) { return 'Unknown error.' }
    if ($Text -match '"message"\s*:\s*"((?:[^"\\]|\\.)*)"') {
        $m = $Matches[1] -replace '\\u0027', "'" -replace '\\"', '"' -replace '\\r\\n|\\n', ' '
        return $m.Trim()
    }
    return ($Text -replace '^Web API \w+ \S+ failed with \d+\.\s*', '').Trim()
}

function Build-CcWritePayload {
    <#
    .SYNOPSIS
        The body for one source record, aimed at the target. Copies the table plan's data columns
        (only those valid for this kind of write), binds each lookup to the target record it points
        at, rewrites GUIDs inside definitions, and returns the lookups that have to wait for the link
        pass. Blocked = something the write cannot do without.
    #>
    param(
        [pscustomobject] $SourceRecord,
        [pscustomobject] $TablePlan,
        [ValidateSet('create', 'update')] [string] $Op,
        [hashtable] $Maps,
        [hashtable] $TablePlans
    )

    $payload = [ordered]@{}
    $deferred = [System.Collections.Generic.List[object]]::new()
    $problems = [System.Collections.Generic.List[string]]::new()
    $blocked = $false
    $attrs = $TablePlan.TargetSchema.Attributes

    foreach ($col in $TablePlan.DataColumns) {
        $a = $attrs[$col]
        if (-not $a) { continue }
        if ($Op -eq 'create' -and -not $a.Create) { continue }
        if ($Op -eq 'update' -and -not $a.Update) { continue }
        $val = $SourceRecord.$col

        if (@($TablePlan.Table.guidBearingColumns) -contains $col -and $val) {
            $rw = ConvertTo-CcTargetDefinition -Definition ([string]$val) -SourceGuidToRef $Maps.SourceGuidToRef -TargetKeyToGuid $Maps.TargetKeyToGuid
            if ($rw.Unmapped.Count -gt 0) {
                $names = @($rw.Unmapped | ForEach-Object { Get-CcRefLabel $Maps $_.Entity $_.Key $TablePlans }) | Select-Object -Unique
                $problems.Add("Its $($a.Label.ToLowerInvariant()) refers to $($names -join ', '), not in the target.") | Out-Null
                $blocked = $true
            }
            $val = $rw.Text
        }
        # On create, an empty value is simply left out; on update it clears the setting.
        if ($null -eq $val -and $Op -eq 'create') { continue }
        $payload[$col] = $val
    }

    foreach ($lk in $TablePlan.Lookups) {
        $a = $attrs[$lk.Column]
        if (-not $a -or -not $lk.Writable) { continue }
        if ($Op -eq 'create' -and -not $a.Create) { continue }
        if ($Op -eq 'update' -and -not $a.Update) { continue }
        $guid = ([string]$SourceRecord.($lk.ValueCol)).ToLowerInvariant()
        if (-not $guid) { continue }
        $ref = $Maps.SourceGuidToRef[$guid]
        if (-not $ref) {
            if ($lk.Required) { $problems.Add("Its $($lk.Label.ToLowerInvariant()) points at a record that no longer exists in the source.") | Out-Null; $blocked = $true }
            continue
        }
        if ($lk.Deferred) {
            $deferred.Add([pscustomobject]@{ Lookup = $lk; Entity = $ref.Entity; Key = $ref.Key }) | Out-Null
            continue
        }
        $targetGuid = $Maps.TargetKeyToGuid["$($ref.Entity)|$($ref.Key)"]
        if (-not $targetGuid) {
            $problems.Add("Its $($lk.Label.ToLowerInvariant()) is $(Get-CcRefLabel $Maps $ref.Entity $ref.Key $TablePlans), which is not in the target.") | Out-Null
            $blocked = $true
            continue
        }
        $set = $TablePlans[$ref.Entity].EntitySet
        $payload["$($lk.Nav)@odata.bind"] = "/$set($targetGuid)"
    }

    return [pscustomobject]@{ Payload = $payload; Deferred = @($deferred); Problems = @($problems); Blocked = $blocked }
}

function Invoke-CcUpsert {
    <#
    .SYNOPSIS
        Writes one record: PATCH when it exists in the target, POST when it does not. Returns the
        record's id in the target.
    #>
    param(
        [pscustomobject] $Environment,
        [string] $EntitySet,
        [string] $PrimaryId,
        [System.Collections.IDictionary] $Payload,
        [string] $TargetGuid
    )
    if ($TargetGuid) {
        Invoke-CcWebApi -Environment $Environment -Method Patch -Path "$EntitySet($TargetGuid)" -Body $Payload -Prefer $null | Out-Null
        return $TargetGuid
    }
    $res = Invoke-CcWebApi -Environment $Environment -Method Post -Path $EntitySet -Body $Payload -Prefer "return=representation,odata.include-annotations=`"*`""
    $id = $null
    if ($res -and $res.$PrimaryId) { $id = ([string]$res.$PrimaryId).ToLowerInvariant() }
    return $id
}

function Wait-CcProvisioning {
    <#
    .SYNOPSIS
        After creating a workstream, waits until Dataverse has provisioned it. There is no public
        "done" flag. What it provisions is the workstream's routing contract (a decision contract,
        set on the workstream some 15-20 seconds after the create); it does not create a routing
        configuration, so waiting for one only ever ran out the timeout. Waiting matters: the link
        pass sets the routing contract to the one the moved rulesets use, and provisioning that
        finished after it would overwrite it.
    #>
    param([pscustomobject] $Environment, [string] $WorkstreamId, [int] $TimeoutSeconds = 60)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $path = "msdyn_liveworkstreams($WorkstreamId)?`$select=_msdyn_routingcontractid_value"
    while ((Get-Date) -lt $deadline) {
        $r = Invoke-CcWebApi -Environment $Environment -Method Get -Path $path
        if ($r -and $r._msdyn_routingcontractid_value) { return $true }
        Start-Sleep -Seconds 3
    }
    return $false
}

function New-CcSnapshotEntry {
    <#
    .SYNOPSIS
        The state of one existing target record before a run changes it, in a form rollback can write
        straight back: its data columns and the lookups it pointed at.
    #>
    param([pscustomobject] $TargetRecord, [pscustomobject] $TablePlan, [string] $TargetId, [hashtable] $TablePlans)
    $data = [ordered]@{}
    foreach ($col in $TablePlan.DataColumns) {
        $a = $TablePlan.TargetSchema.Attributes[$col]
        if ($a -and $a.Update) { $data[$col] = $TargetRecord.$col }
    }
    $binds = [ordered]@{}
    foreach ($lk in $TablePlan.Lookups) {
        $a = $TablePlan.TargetSchema.Attributes[$lk.Column]
        if (-not $a -or -not $a.Update) { continue }
        $g = [string]$TargetRecord.($lk.ValueCol)
        $binds[$lk.Nav] = if ($g) { "/$($TablePlans[$lk.Target].EntitySet)($g)" } else { $null }
    }
    return [ordered]@{
        table     = $TablePlan.LogicalName
        entitySet = $TablePlan.EntitySet
        id        = $TargetId
        data      = $data
        binds     = $binds
    }
}
