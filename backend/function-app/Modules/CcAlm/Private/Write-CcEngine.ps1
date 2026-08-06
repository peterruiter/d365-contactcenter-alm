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
        [ref] $Problems
    )

    $skip = @($SystemColumns)
    if ($Table.skipColumns)  { $skip += $Table.skipColumns }
    if ($Table.stripColumns) { $skip += $Table.stripColumns }

    $payload = [ordered]@{}
    $pk = "$($Table.logicalName)id"
    $lookupValueCols = @($Table.lookups | ForEach-Object { "_$($_.column)_value" })

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
                $Problems.Value.Add("Ruleset '$($SourceRecord.$($Table.matchKeys[0]))' has unmapped GUIDs: $($rw.Unmapped -join ', ')") | Out-Null
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

        $refIdx = $SourceIndexes[$lk.target]
        $refKey = if ($refIdx -and $refIdx.IdToKey.ContainsKey($srcGuid)) { $refIdx.IdToKey[$srcGuid] } else { $null }
        if (-not $refKey) {
            $Problems.Value.Add("$($Table.logicalName): lookup $($lk.column) points at a source record with no natural key.") | Out-Null
            continue
        }

        $targetGuid = $Maps.TargetKeyToGuid["$($lk.target)|$refKey"]
        if (-not $targetGuid) {
            $Problems.Value.Add("$($Table.logicalName): parent $($lk.target) '$refKey' not found in target. Write parents first.") | Out-Null
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

    return $payload
}

function Invoke-CcUpsert {
    <#
    .SYNOPSIS
        Writes one record. Upserts by alternate key when the table has one, otherwise decides create vs
        update from the target index. Honours create-once via If-None-Match.
    #>
    param(
        [pscustomobject] $Environment,
        [pscustomobject] $Table,
        [hashtable] $Payload,
        [string] $AltKeyValue,
        [string] $TargetGuid,
        [switch] $CreateOnce
    )

    $set = $Table.entitySet
    $headers = @{}
    if ($CreateOnce) { $headers['If-None-Match'] = '*' }

    if ($Table.alternateKey -and $AltKeyValue) {
        $encoded = [uri]::EscapeDataString($AltKeyValue)
        $path = "$set($($Table.alternateKey)='$encoded')"
        return Invoke-CcWebApi -Environment $Environment -Method Patch -Path $path -Body $Payload -ExtraHeaders $headers -Prefer 'return=representation'
    }

    if ($TargetGuid) {
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
        [string] $Path
    )

    $snapshot = [ordered]@{
        environment = $Environment.Id
        taken       = (Get-Date).ToString('o')
        records     = @{}
    }

    foreach ($op in $Operations) {
        $idx = $TargetIndexes[$op.table]
        if (-not $idx) { continue }
        # best-effort: store any existing target row for this match key
        foreach ($guid in $idx.ById.Keys) {
            if ($idx.IdToKey[$guid] -eq $op.matchKey) {
                if (-not $snapshot.records.ContainsKey($op.table)) { $snapshot.records[$op.table] = @() }
                $snapshot.records[$op.table] += $idx.ById[$guid]
            }
        }
    }

    $snapshot | ConvertTo-Json -Depth 40 | Set-Content -Path $Path -Encoding UTF8
    return $Path
}
