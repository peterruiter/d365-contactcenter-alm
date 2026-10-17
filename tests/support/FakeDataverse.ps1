# An in-memory Dataverse for the engine's tests. It answers the Web API calls the engine makes -
# EntityDefinitions, reads with $select and $filter, create, update, delete, lookup binds and
# unbinds - from table metadata and records held in memory, and it is strict where Dataverse is
# strict: an unknown $select column, a column that is not valid for create or update, or a bind to
# a navigation property the table does not have fails the way the real API does.
#
# Mount-CcFakeDataverse puts it under the CcAlm module in place of Invoke-CcWebApi, so compare,
# plan, run, verify and rollback all run exactly as they do against a real org, without a network.

function ConvertTo-CcFakeRecord {
    # A record as Dataverse returns it: a PSCustomObject with ordered properties.
    param([System.Collections.IDictionary] $Values)
    $o = [pscustomobject]@{}
    foreach ($k in $Values.Keys) { $o | Add-Member -NotePropertyName $k -NotePropertyValue $Values[$k] -Force }
    return $o
}

function New-CcFakeOrg {
    <#
    .SYNOPSIS
        One fake environment. Metadata: logical name -> EntityDefinitions response (or $null for a
        table that is not installed). Records: entity set -> records as the Web API returns them.
    #>
    param(
        [Parameter(Mandatory)] [string] $Url,
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Metadata,
        [System.Collections.IDictionary] $Records = @{},
        # Create a routing configuration and step when a workstream is created, as Dataverse does
        # for some workstreams.
        [switch] $ProvisionRoutingConfiguration
    )
    $tables = @{}
    $bySet = @{}
    foreach ($logical in $Metadata.Keys) {
        $m = $Metadata[$logical]
        if (-not $m) { continue }
        $attrs = @{}
        foreach ($a in $m.Attributes) { $attrs[$a.LogicalName] = $a }
        $navs = @{}
        foreach ($r in $m.ManyToOneRelationships) { $navs[$r.ReferencingEntityNavigationPropertyName] = $r }
        $t = [pscustomobject]@{
            Logical     = $logical
            Set         = $m.EntitySetName
            PrimaryId   = $m.PrimaryIdAttribute
            PrimaryName = $m.PrimaryNameAttribute
            Meta        = $m
            Attributes  = $attrs
            Navs        = $navs
            Rows        = [System.Collections.Generic.List[object]]::new()
        }
        $tables[$logical] = $t
        $bySet[$m.EntitySetName] = $t
    }
    foreach ($set in $Records.Keys) {
        $t = $bySet[$set]
        if (-not $t) { continue }
        foreach ($r in @($Records[$set])) { if ($r) { $t.Rows.Add($r) } }
    }
    [pscustomobject]@{
        Url       = $Url.TrimEnd('/')
        Metadata  = $Metadata
        Tables    = $tables
        BySet     = $bySet
        Writes    = [System.Collections.Generic.List[object]]::new()
        # GETs answered: metadata (MetadataReads) and records (RecordReads).
        MetadataReads = 0
        RecordReads   = 0
        Provision = [bool]$ProvisionRoutingConfiguration
        # & $FailWhen <method> <entitySet> <body>: return a message to make that write fail.
        FailWhen  = $null
        # & $OnWrite <method> <entitySet> <record>: runs after a create or update is stored, like a
        # plugin that changes what was written.
        OnWrite   = $null
    }
}

function Copy-CcFakeOrg {
    # A deep copy, so a test can keep the before state of a target it then writes to.
    param([pscustomobject] $Org, [string] $Url = $Org.Url)
    $records = @{}
    foreach ($t in $Org.Tables.Values) {
        $records[$t.Set] = @($t.Rows | ForEach-Object { $_ | ConvertTo-Json -Depth 20 -Compress | ConvertFrom-Json })
    }
    New-CcFakeOrg -Url $Url -Metadata $Org.Metadata -Records $records -ProvisionRoutingConfiguration:$Org.Provision
}

function Get-CcFakeRow {
    param([pscustomobject] $Table, [string] $Id)
    $id = $Id.ToLowerInvariant()
    foreach ($r in $Table.Rows) { if (([string]$r.($Table.PrimaryId)).ToLowerInvariant() -eq $id) { return $r } }
    return $null
}

function Get-CcFakeName {
    # The primary name of a record anywhere in the org, for lookup annotations.
    param([pscustomobject] $Org, [string] $Logical, [string] $Id)
    $t = $Org.Tables[$Logical]
    if (-not $t) { return $null }
    $r = Get-CcFakeRow $t $Id
    if ($r -and $t.PrimaryName) { return $r.($t.PrimaryName) }
    return $null
}

function Set-CcFakeLookup {
    # Sets _col_value and its annotations, the way a read returns a lookup.
    param([pscustomobject] $Org, [pscustomobject] $Record, [string] $Column, [string] $ReferencedEntity, [string] $Id)
    $vc = "_$($Column)_value"
    if (-not $Id) {
        foreach ($n in @($vc, "$vc@Microsoft.Dynamics.CRM.lookuplogicalname", "$vc@OData.Community.Display.V1.FormattedValue")) {
            $Record | Add-Member -NotePropertyName $n -NotePropertyValue $null -Force
        }
        return
    }
    $Record | Add-Member -NotePropertyName $vc -NotePropertyValue $Id.ToLowerInvariant() -Force
    $Record | Add-Member -NotePropertyName "$vc@Microsoft.Dynamics.CRM.lookuplogicalname" -NotePropertyValue $ReferencedEntity -Force
    $Record | Add-Member -NotePropertyName "$vc@OData.Community.Display.V1.FormattedValue" -NotePropertyValue (Get-CcFakeName $Org $ReferencedEntity $Id) -Force
}

function Get-CcFakeError {
    param([string] $Method, [string] $Path, [int] $Status, [string] $Message)
    $json = @{ error = @{ code = '0x80040203'; message = $Message } } | ConvertTo-Json -Compress
    return "Web API $Method $Path failed with $Status. $json"
}

function Set-CcFakeValues {
    # Applies a create or update body to a record: plain columns and @odata.bind lookups.
    param([pscustomobject] $Org, [pscustomobject] $Table, [pscustomobject] $Record, [System.Collections.IDictionary] $Body, [ValidateSet('create', 'update')] [string] $Op, [string] $Method, [string] $Path)
    foreach ($k in $Body.Keys) {
        $v = $Body[$k]
        if ($k -match '^(.+)@odata\.bind$') {
            $nav = $Matches[1]
            $rel = $Table.Navs[$nav]
            if (-not $rel) { throw (Get-CcFakeError $Method $Path 400 "An undeclared property '$nav' which only has property annotations in the payload but no property value was found in the payload.") }
            if ([string]$v -notmatch '^/?([A-Za-z_]+)\(([0-9a-fA-F-]{36})\)$') { throw (Get-CcFakeError $Method $Path 400 "Bad bind value '$v'.") }
            $set, $id = $Matches[1], $Matches[2]
            $refTable = $Org.BySet[$set]
            if (-not $refTable -or $refTable.Logical -ne $rel.ReferencedEntity) { throw (Get-CcFakeError $Method $Path 400 "'$set' is not the table '$nav' points at.") }
            if (-not (Get-CcFakeRow $refTable $id)) { throw (Get-CcFakeError $Method $Path 404 "$($refTable.Logical) With Id = $id Does Not Exist") }
            Set-CcFakeLookup $Org $Record $rel.ReferencingAttribute $rel.ReferencedEntity $id
            continue
        }
        $a = $Table.Attributes[$k]
        if (-not $a) { throw (Get-CcFakeError $Method $Path 400 "Invalid property '$k' was found in entity 'Microsoft.Dynamics.CRM.$($Table.Logical)'.") }
        if ($Op -eq 'create' -and -not $a.IsValidForCreate -and $k -ne $Table.PrimaryId) { throw (Get-CcFakeError $Method $Path 400 "Field '$k' is not valid for create.") }
        if ($Op -eq 'update' -and -not $a.IsValidForUpdate) { throw (Get-CcFakeError $Method $Path 400 "Field '$k' is not valid for update.") }
        $Record | Add-Member -NotePropertyName $k -NotePropertyValue $v -Force
        # The label read back for a choice or a date belonged to the old value.
        if ($Record.PSObject.Properties.Name -contains "$k@OData.Community.Display.V1.FormattedValue") {
            $Record | Add-Member -NotePropertyName "$k@OData.Community.Display.V1.FormattedValue" -NotePropertyValue $null -Force
        }
    }
}

function Add-CcFakeRecord {
    <#
    .SYNOPSIS
        Puts a record straight into a fake org, for building test data. Lookups are given as
        @{ column = guid }; the id is generated when not given. Returns the id.
    #>
    param(
        [Parameter(Mandatory)] [pscustomobject] $Org,
        [Parameter(Mandatory)] [string] $Table,
        [System.Collections.IDictionary] $Values = @{},
        [System.Collections.IDictionary] $Lookups = @{},
        [string] $Id = ([guid]::NewGuid().ToString()),
        [bool] $Managed = $false
    )
    $t = $Org.Tables[$Table]
    if (-not $t) { throw "Fake org has no table $Table." }
    $r = [pscustomobject]@{}
    $r | Add-Member -NotePropertyName $t.PrimaryId -NotePropertyValue $Id.ToLowerInvariant()
    if ($t.Attributes.ContainsKey('ismanaged')) { $r | Add-Member -NotePropertyName ismanaged -NotePropertyValue $Managed }
    foreach ($k in $Values.Keys) {
        if (-not $t.Attributes.ContainsKey($k)) { throw "Table $Table has no column $k." }
        $r | Add-Member -NotePropertyName $k -NotePropertyValue $Values[$k] -Force
    }
    foreach ($col in $Lookups.Keys) {
        $rel = $t.Meta.ManyToOneRelationships | Where-Object ReferencingAttribute -eq $col | Select-Object -First 1
        if (-not $rel) { throw "Table $Table has no lookup $col." }
        Set-CcFakeLookup $Org $r $col $rel.ReferencedEntity $Lookups[$col]
    }
    $t.Rows.Add($r)
    return $Id.ToLowerInvariant()
}

function Add-CcFakeAssociation {
    # Links two records through a many-to-many relationship, as a row of its intersect table.
    param([pscustomobject] $Org, [string] $SchemaName, [string] $Id1, [string] $Id2)
    $m2m = $Org.Tables.Values | ForEach-Object { @($_.Meta.ManyToManyRelationships) } | Where-Object { $_ -and $_.SchemaName -eq $SchemaName } | Select-Object -First 1
    if (-not $m2m) { throw "Fake org has no relationship $SchemaName." }
    $it = $Org.Tables[$m2m.IntersectEntityName]
    if (-not $it) { throw "Fake org has no intersect table $($m2m.IntersectEntityName)." }
    $r = [pscustomobject]@{}
    $r | Add-Member -NotePropertyName $it.PrimaryId -NotePropertyValue ([guid]::NewGuid().ToString())
    $r | Add-Member -NotePropertyName $m2m.Entity1IntersectAttribute -NotePropertyValue $Id1.ToLowerInvariant()
    $r | Add-Member -NotePropertyName $m2m.Entity2IntersectAttribute -NotePropertyValue $Id2.ToLowerInvariant()
    $it.Rows.Add($r)
}

function Select-CcFakeColumns {
    # A row as a $select read returns it: the asked-for columns (null when the row has no value)
    # and their annotations.
    param([pscustomobject] $Row, [string[]] $Select)
    $o = [ordered]@{ '@odata.etag' = 'W/"1"' }
    $names = @($Row.PSObject.Properties.Name)
    foreach ($c in $Select) {
        $o[$c] = $Row.$c
        foreach ($n in $names) { if ($n.StartsWith("$c@")) { $o[$n] = $Row.$n } }
    }
    return ConvertTo-CcFakeRecord $o
}

function Invoke-CcFakeRequest {
    <#
    .SYNOPSIS
        Answers one Web API call against a fake org: the same contract as Invoke-CcWebApi.
    #>
    param([pscustomobject] $Org, [string] $Method, [string] $Path, $Body)

    $p = $Path -replace '^https?://[^/]+/api/data/v[\d.]+/', ''
    $body = $Body
    if ($body -is [string]) { $body = $body | ConvertFrom-Json -AsHashtable }
    elseif ($body -and $body -isnot [System.Collections.IDictionary]) {
        $h = [ordered]@{}; foreach ($pp in $body.PSObject.Properties) { $h[$pp.Name] = $pp.Value }; $body = $h
    }

    if ($p -eq 'WhoAmI') { return [pscustomobject]@{ UserId = '00000000-0000-0000-0000-00000000aaaa' } }

    if ($p -match "^EntityDefinitions\(LogicalName='([^']+)'\)") {
        $Org.MetadataReads++
        $m = $Org.Metadata[$Matches[1]]
        if (-not $m) { throw (Get-CcFakeError $Method $p 404 "Could not find an entity with name $($Matches[1]).") }
        return $m
    }

    if ($p -notmatch '^([A-Za-z_]+)(?:\(([0-9a-fA-F-]{36})\))?(?:/([A-Za-z_]+)(?:\(([0-9a-fA-F-]{36})\))?/\$ref)?(?:\?(.*))?$') {
        throw (Get-CcFakeError $Method $p 400 "The fake does not understand '$p'.")
    }
    $set, $id, $refNav, $refId, $query = $Matches[1], $Matches[2], $Matches[3], $Matches[4], $Matches[5]
    $t = $Org.BySet[$set]
    if (-not $t) { throw (Get-CcFakeError $Method $p 404 "Resource not found for the segment '$set'.") }

    if ($Method -ne 'Get') {
        if ($Org.FailWhen) {
            $msg = & $Org.FailWhen $Method $set $body
            if ($msg) { throw (Get-CcFakeError $Method $p 400 $msg) }
        }
        $Org.Writes.Add([pscustomobject]@{ Method = $Method; Set = $set; Id = $id; Nav = $refNav; Body = $body }) | Out-Null
    }

    # A many-to-many link: POST set(id)/nav/$ref with @odata.id, DELETE set(id)/nav(otherId)/$ref.
    $m2m = if ($refNav) { @($t.Meta.ManyToManyRelationships) | Where-Object { $_ -and ($_.Entity1NavigationPropertyName -eq $refNav -or $_.Entity2NavigationPropertyName -eq $refNav) } | Select-Object -First 1 } else { $null }
    if ($m2m -and $Method -in 'Post', 'Delete') {
        if (-not (Get-CcFakeRow $t $id)) { throw (Get-CcFakeError $Method $p 404 "$($t.Logical) With Id = $id Does Not Exist") }
        $otherLogical = if ($t.Logical -eq $m2m.Entity1LogicalName) { $m2m.Entity2LogicalName } else { $m2m.Entity1LogicalName }
        $otherId = $refId
        if ($Method -eq 'Post') {
            if ([string]$body.'@odata.id' -notmatch '/([A-Za-z_]+)\(([0-9a-fA-F-]{36})\)$') { throw (Get-CcFakeError $Method $p 400 'Bad @odata.id.') }
            $otherId = $Matches[2]
            if (-not (Get-CcFakeRow $Org.Tables[$otherLogical] $otherId)) { throw (Get-CcFakeError $Method $p 404 "$otherLogical With Id = $otherId Does Not Exist") }
        }
        $id1 = if ($t.Logical -eq $m2m.Entity1LogicalName) { $id } else { $otherId }
        $id2 = if ($t.Logical -eq $m2m.Entity1LogicalName) { $otherId } else { $id }
        $it = $Org.Tables[$m2m.IntersectEntityName]
        $existing = @($it.Rows | Where-Object { ([string]$_.($m2m.Entity1IntersectAttribute)) -eq $id1.ToLowerInvariant() -and ([string]$_.($m2m.Entity2IntersectAttribute)) -eq $id2.ToLowerInvariant() })
        if ($Method -eq 'Post') {
            if ($existing) { throw (Get-CcFakeError $Method $p 400 'Cannot insert duplicate key.') }
            Add-CcFakeAssociation $Org $m2m.SchemaName $id1 $id2
        }
        else {
            if (-not $existing) { throw (Get-CcFakeError $Method $p 404 'The association does not exist.') }
            foreach ($e in $existing) { [void]$it.Rows.Remove($e) }
        }
        return $null
    }

    switch ($Method) {
        'Get' {
            $Org.RecordReads++
            $q = @{}
            foreach ($part in ([string]$query -split '&')) {
                if ($part -match '^\$(\w+)=(.*)$') { $q[$Matches[1]] = [uri]::UnescapeDataString($Matches[2]) }
            }
            $rows = @($t.Rows)
            if ($id) { $rows = @(Get-CcFakeRow $t $id | Where-Object { $_ }) }
            if ($q.filter) {
                if ($q.filter -notmatch '^(\w+) eq ([0-9a-fA-F-]{36})$') { throw (Get-CcFakeError $Method $p 400 "The fake only filters on '<column> eq <guid>'.") }
                $col, $val = $Matches[1], $Matches[2].ToLowerInvariant()
                $rows = @($rows | Where-Object { ([string]$_.$col).ToLowerInvariant() -eq $val })
            }
            $select = if ($q.select) { @($q.select -split ',') } else { @($t.Attributes.Keys) }
            foreach ($c in $select) {
                $bare = $c -replace '^_' -replace '_value$'
                if (-not $t.Attributes.ContainsKey($bare)) { throw (Get-CcFakeError $Method $p 400 "Could not find a property named '$c' on type 'Microsoft.Dynamics.CRM.$($t.Logical)'.") }
            }
            $out = @($rows | ForEach-Object { Select-CcFakeColumns $_ $select })
            if ($id) { return $out[0] }
            return [pscustomobject]@{ value = $out }
        }
        'Post' {
            $newId = [guid]::NewGuid().ToString()
            $r = [pscustomobject]@{}
            $r | Add-Member -NotePropertyName $t.PrimaryId -NotePropertyValue $newId
            if ($t.Attributes.ContainsKey('ismanaged')) { $r | Add-Member -NotePropertyName ismanaged -NotePropertyValue $false }
            Set-CcFakeValues $Org $t $r $body 'create' $Method $p
            $t.Rows.Add($r)
            if ($Org.OnWrite) { & $Org.OnWrite $Method $set $r }
            if ($Org.Provision -and $t.Logical -eq 'msdyn_liveworkstream') {
                $name = "Workstream: $($r.msdyn_name) ($newId)"
                $rc = Add-CcFakeRecord $Org 'msdyn_routingconfiguration' @{ msdyn_name = "RC - $name"; msdyn_uniquename = "rc_$($newId -replace '-')"; msdyn_isactiveconfiguration = $true } @{ msdyn_liveworkstreamid = $newId }
                Add-CcFakeRecord $Org 'msdyn_routingconfigurationstep' @{ msdyn_name = "RCS - $name"; msdyn_uniquename = "rcs_$($newId -replace '-')" } @{ msdyn_routingconfigurationid = $rc } | Out-Null
            }
            return $r
        }
        'Patch' {
            $r = Get-CcFakeRow $t $id
            if (-not $r) { throw (Get-CcFakeError $Method $p 404 "$($t.Logical) With Id = $id Does Not Exist") }
            Set-CcFakeValues $Org $t $r $body 'update' $Method $p
            if ($Org.OnWrite) { & $Org.OnWrite $Method $set $r }
            return $null
        }
        'Delete' {
            $r = Get-CcFakeRow $t $id
            if (-not $r) { throw (Get-CcFakeError $Method $p 404 "$($t.Logical) With Id = $id Does Not Exist") }
            if ($refNav) {
                $rel = $t.Navs[$refNav]
                if (-not $rel) { throw (Get-CcFakeError $Method $p 400 "No navigation property '$refNav'.") }
                Set-CcFakeLookup $Org $r $rel.ReferencingAttribute $rel.ReferencedEntity $null
                return $null
            }
            [void]$t.Rows.Remove($r)
            return $null
        }
    }
}

function New-CcFakeEnvironment {
    # The connected-environment object the engine's cmdlets take, pointing at a fake org.
    param([string] $Id, [string] $Name, [pscustomobject] $Org, [bool] $RequireApproval = $false)
    [pscustomobject]@{
        Id = $Id; Name = $Name; Url = $Org.Url; Role = 'any'; RequireApproval = $RequireApproval
        ApiVersion = 'v9.2'; TenantId = 'fake'; ClientId = 'fake'; ClientSecret = 'fake'
    }
}

function Mount-CcFakeDataverse {
    <#
    .SYNOPSIS
        Imports a fresh copy of the CcAlm module whose Web API calls go to these fake orgs (by URL)
        and whose clock is virtual: Start-Sleep moves it on instead of waiting, and every call
        takes LatencySeconds of it. A 90-second provisioning wait or a 7-minute time budget then
        passes in milliseconds, and the same way every time.
        Returns @{ Module; Clock }; Clock.Offset is how far the virtual clock is ahead.
    #>
    param(
        [Parameter(Mandatory)] [pscustomobject[]] $Orgs,
        [double] $LatencySeconds = 0
    )
    $modulePath = Join-Path $PSScriptRoot '../../backend/function-app/Modules/CcAlm/CcAlm.psd1'
    Import-Module $modulePath -Force -DisableNameChecking
    $module = Get-Module CcAlm
    $byUrl = @{}
    foreach ($o in $Orgs) { $byUrl[$o.Url] = $o }
    $clock = @{ Offset = 0.0; Latency = $LatencySeconds; Calls = 0 }
    $handler = ${function:Invoke-CcFakeRequest}
    & $module {
        param($byUrl, $handler, $clock)
        $script:CcFakeOrgs = $byUrl
        $script:CcFakeHandler = $handler
        $script:CcFakeClock = $clock
        function script:Invoke-CcWebApi {
            param($Environment, $Method, $Path, $Body, $ExtraHeaders, $Prefer, $MaxRetries)
            $org = $script:CcFakeOrgs[$Environment.Url.TrimEnd('/')]
            if (-not $org) { throw "No fake org for $($Environment.Url)." }
            $script:CcFakeClock.Calls++
            $script:CcFakeClock.Offset += $script:CcFakeClock.Latency
            & $script:CcFakeHandler -Org $org -Method $Method -Path $Path -Body $Body
        }
        function script:Start-Sleep {
            param($Seconds, $Milliseconds)
            $script:CcFakeClock.Offset += [double]$Seconds + ([double]$Milliseconds / 1000)
        }
        function script:Get-Date {
            param([string] $Format)
            $now = (Microsoft.PowerShell.Utility\Get-Date).AddSeconds($script:CcFakeClock.Offset)
            if ($Format) { return $now.ToString($Format) }
            return $now
        }
    } $byUrl $handler $clock
    return [pscustomobject]@{ Module = $module; Clock = $clock }
}
