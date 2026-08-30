$script:CcNavCache = @{}

function Get-CcNavProperty {
    <#
    .SYNOPSIS
        Returns the single-valued navigation property name for a lookup column, read from entity
        metadata and cached. Needed because @odata.bind uses the nav property, not the logical column.
    #>
    param(
        [pscustomobject] $Environment,
        [string] $EntityLogicalName,
        [string] $ReferencingAttribute
    )

    $cacheKey = "$($Environment.Id)|$EntityLogicalName"
    if (-not $script:CcNavCache.ContainsKey($cacheKey)) {
        $path = "EntityDefinitions(LogicalName='$EntityLogicalName')/ManyToOneRelationships?`$select=ReferencingAttribute,ReferencingEntityNavigationPropertyName"
        $meta = Invoke-CcWebApi -Environment $Environment -Method Get -Path $path
        $map = @{}
        foreach ($rel in $meta.value) {
            $map[$rel.ReferencingAttribute] = $rel.ReferencingEntityNavigationPropertyName
        }
        $script:CcNavCache[$cacheKey] = $map
    }

    $navMap = $script:CcNavCache[$cacheKey]
    if ($navMap.ContainsKey($ReferencingAttribute)) { return $navMap[$ReferencingAttribute] }
    return $null
}

function Build-CcWritePayload {
    <#
    .SYNOPSIS
        Builds the JSON body for a source record targeted at the target environment. Copies data columns,
        binds lookups to target records by resolved GUID, rewrites GUID-bearing definitions, and drops
        system / skip / strip / phone / bot columns.
    #>
    param(
        [pscustomobject] $SourceRecord,
        [pscustomobject] $Table,
        [pscustomobject] $Environment,
        [hashtable] $EntitySetByLogical,
        [hashtable] $SourceIndexes,
        [object] $Maps,
        [string[]] $SystemColumns,
        [ref] $Problems,
        [hashtable] $TableByLogical
    )

    $skip = @($SystemColumns)
    if ($Table.skipColumns)  { $skip += $Table.skipColumns }
    if ($Table.stripColumns) { $skip += $Table.stripColumns }

    $payload = [ordered]@{}
    $pk = "$($Table.logicalName)id"
    $lookupValueCols = @($Table.lookups | ForEach-Object { "_$($_.column)_value" })
    $blocked = $false

    foreach ($col in $Table.select) {
        if ($col -eq $pk) { continue }
        if ($skip -contains $col) { continue }
        if ($lookupValueCols -contains $col) { continue }        # handled below
        if ($col -match '^_.*_value$') { continue }              # unmanaged lookup, skip
        $val = $SourceRecord.$col

        if ($Table.guidBearingColumns -and ($Table.guidBearingColumns -contains $col)) {
            $rw = ConvertTo-CcTargetDefinition -Definition ([string]$val) `
                    -SourceGuidToRef $Maps.SourceGuidToRef -TargetKeyToGuid $Maps.TargetKeyToGuid
            if ($rw.Unmapped.Count -gt 0) {
                # Confirmed empirically: writing a definition with GUIDs Dataverse can't resolve
                # (e.g. a ruleset pointing at a queue that hasn't been migrated yet) is a guaranteed
                # server-side rejection, not a soft warning - the caller skips this write entirely.
                $Problems.Value.Add("Ruleset '$($SourceRecord.$($Table.matchKeys[0]))' has unmapped GUIDs: $($rw.Unmapped -join ', ')") | Out-Null
                $blocked = $true
            }
            $val = $rw.Text
        }

        if ($null -ne $val) { $payload[$col] = $val }
    }

    foreach ($lk in $Table.lookups) {
        $valueCol = "_$($lk.column)_value"
        if ($SourceRecord.PSObject.Properties.Name -notcontains $valueCol) { continue }
        $srcGuid = [string]$SourceRecord.$valueCol
        if (-not $srcGuid) { continue }
        if (($Table.stripColumns) -and ($Table.stripColumns -contains $valueCol)) { continue }

        # Resolve to the referenced record's RESOLVED comparable key, not Build-CcIndex's raw
        # IdToKey. For a target table whose own matchKeys include a lookup column (e.g. a routing
        # config matched on name plus its parent workstream), the raw key embeds that lookup's GUID
        # as-is - a different, environment-specific value on each side - so it can never agree with
        # $Maps.TargetKeyToGuid below, which is now built the same resolved way.
        $refIdx = $SourceIndexes[$lk.target]
        $refTable = $TableByLogical[$lk.target]
        $refKey = if ($refIdx -and $refTable -and $refIdx.ById.ContainsKey($srcGuid)) {
            Get-CcComparableKey -Record $refIdx.ById[$srcGuid] -Table $refTable -EnvIndexes $SourceIndexes
        } else { $null }
        if (-not $refKey) {
            $Problems.Value.Add("$($Table.logicalName): lookup $($lk.column) points at a source record with no natural key.") | Out-Null
            $blocked = $true
            continue
        }

        $targetGuid = $Maps.TargetKeyToGuid["$($lk.target)|$refKey"]
        if (-not $targetGuid) {
            # The source record is genuinely linked to this parent, but the parent hasn't landed in
            # target - writing anyway would silently drop the relationship (or fail outright if the
            # lookup is required). Block it like an unmapped guidBearingColumns reference: skip the
            # write, keep the reason in Problems, let the caller move on instead of aborting the run.
            $Problems.Value.Add("$($Table.logicalName): parent $($lk.target) '$refKey' not found in target. Write parents first.") | Out-Null
            $blocked = $true
            continue
        }

        $nav = Get-CcNavProperty -Environment $Environment -EntityLogicalName $Table.logicalName -ReferencingAttribute $lk.column
        if (-not $nav) {
            $Problems.Value.Add("$($Table.logicalName): no navigation property for $($lk.column). Confirm metadata.") | Out-Null
            continue
        }
        $refSet = $EntitySetByLogical[$lk.target]
        $payload["$nav@odata.bind"] = "/$refSet($targetGuid)"
    }

    return [pscustomobject]@{ Payload = $payload; Blocked = $blocked }
}

function Invoke-CcUpsert {
    <#
    .SYNOPSIS
        Writes one record. Decides create vs update from the target index, resolved by compare - not
        from a Dataverse alternate key, since alternate keys are org-specific metadata that may not
        exist even when the manifest names a natural key. CreateOnce skips the write entirely when the
        record already exists in target, matching "insert only if missing" without depending on
        If-None-Match against a key that might not be published.
    #>
    param(
        [pscustomobject] $Environment,
        [pscustomobject] $Table,
        [hashtable] $Payload,
        [string] $TargetGuid,
        [switch] $CreateOnce
    )

    $set = $Table.entitySet

    if ($TargetGuid) {
        if ($CreateOnce) { return $null }
        $path = "$set($TargetGuid)"
        return Invoke-CcWebApi -Environment $Environment -Method Patch -Path $path -Body $Payload -Prefer 'return=representation'
    }

    return Invoke-CcWebApi -Environment $Environment -Method Post -Path $set -Body $Payload -Prefer 'return=representation'
}

function Wait-CcProvisioning {
    <#
    .SYNOPSIS
        After a workstream write, polls for the expected provisioning side-effect and warns on timeout.
        There is no public done flag, so this is empirical.
    #>
    param(
        [pscustomobject] $Environment,
        [string] $WorkstreamName,
        [int] $TimeoutSeconds = 60
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $encoded = [uri]::EscapeDataString($WorkstreamName)
    $path = "msdyn_liveworkstreams?`$filter=msdyn_name eq '$encoded'&`$select=msdyn_liveworkstreamid,statecode"

    while ((Get-Date) -lt $deadline) {
        $r = Invoke-CcWebApi -Environment $Environment -Method Get -Path $path
        if ($r.value -and $r.value.Count -gt 0) {
            # Workstream exists. Real deployments also poll for a default queue / channel side-effect here.
            Start-Sleep -Seconds 3
            return $true
        }
        Start-Sleep -Seconds 5
    }

    Write-Warning "Provisioning not confirmed for workstream '$WorkstreamName' within $TimeoutSeconds s."
    return $false
}

function Save-CcSnapshot {
    <#
    .SYNOPSIS
        Snapshots the target records a plan will touch, so a failed run can be restored.
    #>
    param(
        [pscustomobject] $Environment,
        [AllowEmptyCollection()] [object[]] $Operations,
        [hashtable] $TargetIndexes,
        [hashtable] $TableByLogical,
        [string] $Path
    )

    $snapshot = [ordered]@{
        environment = $Environment.Id
        taken       = (Get-Date).ToString('o')
        records     = @{}
    }

    foreach ($op in $Operations) {
        $idx = $TargetIndexes[$op.table]
        $tbl = $TableByLogical[$op.table]
        if (-not $idx -or -not $tbl) { continue }
        # best-effort: store any existing target row for this match key. Compares the RESOLVED
        # comparable key, matching $op.matchKey's own format - the raw IdToKey never agrees with it
        # for a table whose own matchKeys include a lookup column (msdyn_routingconfiguration and
        # friends), which silently snapshotted zero rows for those tables before this fix.
        foreach ($guid in $idx.ById.Keys) {
            $key = Get-CcComparableKey -Record $idx.ById[$guid] -Table $tbl -EnvIndexes $TargetIndexes
            if ($key -eq $op.matchKey) {
                if (-not $snapshot.records.ContainsKey($op.table)) { $snapshot.records[$op.table] = @() }
                $snapshot.records[$op.table] += $idx.ById[$guid]
            }
        }
    }

    $snapshot | ConvertTo-Json -Depth 40 | Set-Content -Path $Path -Encoding UTF8
    return $Path
}
