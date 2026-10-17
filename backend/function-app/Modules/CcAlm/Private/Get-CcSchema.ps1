# Schema-driven tables. The manifest says WHICH tables move, in what order and how records match;
# the environment's own metadata says which columns and lookups those tables have. Hand-kept column
# lists drifted from real Dataverse (lookups renamed, settings added every release) and silently
# stopped comparing or moving most of the configuration, so the engine now asks each org.

$script:CcSchemaCache = @{}
$script:CcSchemaTtlMinutes = 30

# Attribute types that are never data to compare or write.
$script:CcNonDataTypes = @('Lookup', 'Customer', 'Owner', 'Uniqueidentifier', 'Virtual', 'EntityName',
    'PartyList', 'ManagedProperty', 'CalendarRules', 'State', 'Status')

function Get-CcTableSchema {
    <#
    .SYNOPSIS
        Columns, lookups and names of one table in one environment, from EntityDefinitions. Cached per
        environment for half an hour. A table that does not exist in the org (a channel that is not
        installed) comes back with Exists = $false rather than throwing.
    #>
    param(
        [Parameter(Mandatory)] [pscustomobject] $Environment,
        [Parameter(Mandatory)] [string] $LogicalName
    )

    $cacheKey = "$($Environment.Url)|$LogicalName"
    $cached = $script:CcSchemaCache[$cacheKey]
    # With a read cache in use, metadata goes through it, so the cache ends up complete even on a
    # process that already had this table's schema.
    if (-not $script:CcReadCache -and $cached -and $cached.LoadedAt -gt (Get-Date).AddMinutes(-$script:CcSchemaTtlMinutes)) { return $cached }

    $path = "EntityDefinitions(LogicalName='$LogicalName')?`$select=LogicalName,EntitySetName,PrimaryIdAttribute,PrimaryNameAttribute,DisplayCollectionName" +
        "&`$expand=Attributes(`$select=LogicalName,AttributeType,IsValidForCreate,IsValidForUpdate,IsValidForRead,RequiredLevel,AttributeOf,DisplayName)," +
        "ManyToOneRelationships(`$select=ReferencingAttribute,ReferencedEntity,ReferencingEntityNavigationPropertyName)," +
        "ManyToManyRelationships(`$select=SchemaName,Entity1LogicalName,Entity2LogicalName,IntersectEntityName,Entity1IntersectAttribute,Entity2IntersectAttribute,Entity1NavigationPropertyName,Entity2NavigationPropertyName)"

    try {
        $d = Invoke-CcCachedGet -Environment $Environment -Path $path -Kind schema -Prefer $null
    }
    catch {
        if ($_.Exception.Message -match '404|does not exist|Could not find') {
            $schema = [pscustomobject]@{ LogicalName = $LogicalName; Exists = $false; LoadedAt = Get-Date }
            $script:CcSchemaCache[$cacheKey] = $schema
            return $schema
        }
        throw
    }

    $attributes = @{}
    foreach ($a in $d.Attributes) {
        if ($a.AttributeOf) { continue }   # name/yomi shadows of lookups and choices
        $label = $null
        if ($a.DisplayName -and $a.DisplayName.UserLocalizedLabel) { $label = $a.DisplayName.UserLocalizedLabel.Label }
        $attributes[$a.LogicalName] = [pscustomobject]@{
            Name     = $a.LogicalName
            Type     = [string]$a.AttributeType
            Read     = [bool]$a.IsValidForRead
            Create   = [bool]$a.IsValidForCreate
            Update   = [bool]$a.IsValidForUpdate
            Required = ($a.RequiredLevel.Value -in 'ApplicationRequired', 'SystemRequired')
            Label    = if ($label) { $label } else { $a.LogicalName }
        }
    }

    # One column can point at several tables (customer, regarding); keep every target.
    $lookups = @{}
    foreach ($r in $d.ManyToOneRelationships) {
        $col = $r.ReferencingAttribute
        if (-not $lookups.ContainsKey($col)) {
            $lookups[$col] = [pscustomobject]@{ Column = $col; Targets = [System.Collections.Generic.List[string]]::new(); Nav = @{} }
        }
        if (-not $lookups[$col].Targets.Contains($r.ReferencedEntity)) { $lookups[$col].Targets.Add($r.ReferencedEntity) }
        $lookups[$col].Nav[$r.ReferencedEntity] = $r.ReferencingEntityNavigationPropertyName
    }

    $tableLabel = $LogicalName
    if ($d.DisplayCollectionName -and $d.DisplayCollectionName.UserLocalizedLabel) { $tableLabel = $d.DisplayCollectionName.UserLocalizedLabel.Label }

    $schema = [pscustomobject]@{
        LogicalName = $LogicalName
        Exists      = $true
        EntitySet   = $d.EntitySetName
        PrimaryId   = $d.PrimaryIdAttribute
        PrimaryName = $d.PrimaryNameAttribute
        Label       = $tableLabel
        Attributes  = $attributes
        Lookups     = $lookups
        # Many-to-many relationships (a quick reply on several workstreams); see Get-CcAssociations.
        ManyToMany  = @($d.ManyToManyRelationships | Where-Object { $_ })
        LoadedAt    = Get-Date
    }
    $script:CcSchemaCache[$cacheKey] = $schema
    return $schema
}

function Clear-CcSchemaCache { $script:CcSchemaCache = @{} }

function Resolve-CcTablePlan {
    <#
    .SYNOPSIS
        Works out, for one manifest table between one source and one target, exactly what gets read,
        compared and written: data columns present in both orgs, lookups to other manifest tables (and
        which of them have to be linked after the fact because they point at a table written later),
        required lookups to per-environment records that block a create, and the columns the target
        org lacks.
    #>
    param(
        [Parameter(Mandatory)] [pscustomobject] $Table,
        [Parameter(Mandatory)] [pscustomobject] $SourceSchema,
        [Parameter(Mandatory)] [pscustomobject] $TargetSchema,
        [Parameter(Mandatory)] [pscustomobject] $Manifest,
        [Parameter(Mandatory)] [hashtable] $TableByLogical
    )

    if (-not $SourceSchema.Exists -or -not $TargetSchema.Exists) {
        $where = if (-not $SourceSchema.Exists -and -not $TargetSchema.Exists) { 'either environment' }
                 elseif (-not $SourceSchema.Exists) { 'the source environment' } else { 'the target environment' }
        return [pscustomobject]@{
            Table = $Table; Usable = $false
            Reason = "$(Get-CcTableLabel $Table) is not installed in $where."
            SourceSchema = $SourceSchema; TargetSchema = $TargetSchema
        }
    }

    $exclude = @($Manifest.systemColumns) + @($Manifest.excludeColumns) + @($Table.exclude) + @($Table.stripColumns)
    $exclude = @($exclude | Where-Object { $_ } | ForEach-Object { ($_ -replace '^_' -replace '_value$').ToLowerInvariant() })
    $pk = $SourceSchema.PrimaryId

    $dataColumns = [System.Collections.Generic.List[string]]::new()
    $missingInTarget = [System.Collections.Generic.List[string]]::new()
    foreach ($a in $SourceSchema.Attributes.Values) {
        if (-not $a.Read -or -not ($a.Create -or $a.Update)) { continue }
        if ($a.Name -eq $pk) { continue }
        if ($script:CcNonDataTypes -contains $a.Type) { continue }
        if ($a.Type -in 'Image', 'File') { continue }   # binary payloads are not configuration
        if ($exclude -contains $a.Name.ToLowerInvariant()) { continue }
        if (-not $TargetSchema.Attributes.ContainsKey($a.Name)) { $missingInTarget.Add($a.Name) | Out-Null; continue }
        $dataColumns.Add($a.Name) | Out-Null
    }

    $myOrder = [int]$Table.order
    $lookups = [System.Collections.Generic.List[object]]::new()
    $requiredExternal = [System.Collections.Generic.List[object]]::new()
    foreach ($lk in $SourceSchema.Lookups.Values) {
        $col = $lk.Column
        $attr = $SourceSchema.Attributes[$col]
        if (-not $attr -or -not $attr.Read) { continue }
        if ($exclude -contains $col.ToLowerInvariant()) { continue }
        if ($col -eq $pk) { continue }

        $managedTargets = @($lk.Targets | Where-Object { $TableByLogical.ContainsKey($_) })
        if ($managedTargets.Count -eq 1) {
            if (-not $TargetSchema.Lookups.ContainsKey($col)) { $missingInTarget.Add($col) | Out-Null; continue }
            $targetTable = $TableByLogical[$managedTargets[0]]
            $nav = $TargetSchema.Lookups[$col].Nav[$managedTargets[0]]
            if (-not $nav) { continue }
            $lookups.Add([pscustomobject]@{
                Column   = $col
                ValueCol = "_$($col)_value"
                Target   = $managedTargets[0]
                Nav      = $nav
                Label    = $attr.Label
                Required = $attr.Required
                Writable = ($attr.Create -or $attr.Update)
                # A lookup to a table written at or after this one (a workstream's default queue, a
                # queue's overflow ruleset, a record pointing at its own table) cannot be set when the
                # record is first written. It is linked in a final pass once its target exists.
                Deferred = ([int]$targetTable.order -ge $myOrder)
            }) | Out-Null
        }
        elseif ($managedTargets.Count -eq 0 -and $attr.Required -and $attr.Create) {
            # A create needs a record that is provisioned per environment (an SMS number, a WhatsApp
            # account) and that this tool does not move. Updates of an existing record are fine.
            $requiredExternal.Add([pscustomobject]@{ Column = $col; Label = $attr.Label; Targets = @($lk.Targets) }) | Out-Null
        }
    }

    foreach ($k in $Table.matchKeys) {
        $bare = $k -replace '^_' -replace '_value$'
        if (-not $SourceSchema.Attributes.ContainsKey($bare)) {
            return [pscustomobject]@{
                Table = $Table; Usable = $false
                Reason = "$(Get-CcTableLabel $Table) cannot be matched: column $bare does not exist in this org. The manifest needs updating."
                SourceSchema = $SourceSchema; TargetSchema = $TargetSchema
            }
        }
    }

    # What to read: the key, every data column, every lookup value, plus the columns the manifest
    # uses for matching, filtering and detect-only signals.
    $select = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    [void]$select.Add($pk)
    if ($SourceSchema.PrimaryName) { [void]$select.Add($SourceSchema.PrimaryName) }
    foreach ($c in $dataColumns) { [void]$select.Add($c) }
    foreach ($l in $lookups) { [void]$select.Add($l.ValueCol) }
    foreach ($k in $Table.matchKeys) { [void]$select.Add($k) }
    if ($Table.tieBreaker) { [void]$select.Add($Table.tieBreaker) }
    if ($Table.personalFilterColumn) { [void]$select.Add($Table.personalFilterColumn) }
    if ($SourceSchema.Attributes.ContainsKey('ismanaged')) { [void]$select.Add('ismanaged') }
    foreach ($tr in @($Table.textReferences)) { foreach ($c in (Get-CcTextReferenceColumns -Reference $tr -Schema $SourceSchema)) { [void]$select.Add($c) } }
    foreach ($rule in @($Manifest.detectOnly | Where-Object logicalName -eq $Table.logicalName)) {
        $sig = $rule.signal
        if ($SourceSchema.Lookups.ContainsKey($sig)) { [void]$select.Add("_$($sig)_value") }
        elseif ($SourceSchema.Attributes.ContainsKey($sig)) { [void]$select.Add($sig) }
    }
    # A select column must exist in BOTH orgs or the read on the other side fails.
    $selectList = @($select | Where-Object {
            $bare = $_ -replace '^_' -replace '_value$'
            $SourceSchema.Attributes.ContainsKey($bare) -and $TargetSchema.Attributes.ContainsKey($bare)
        })

    return [pscustomobject]@{
        Table            = $Table
        Usable           = $true
        Reason           = $null
        LogicalName      = $Table.logicalName
        EntitySet        = $TargetSchema.EntitySet
        SourceEntitySet  = $SourceSchema.EntitySet
        PrimaryId        = $pk
        PrimaryName      = $SourceSchema.PrimaryName
        DataColumns      = @($dataColumns)
        Lookups          = @($lookups)
        RequiredExternal = @($requiredExternal)
        MissingInTarget  = @($missingInTarget)
        Select           = $selectList
        SourceSchema     = $SourceSchema
        TargetSchema     = $TargetSchema
    }
}

function Get-CcTextReferenceColumns {
    # A text reference names its column(s) exactly or with a trailing * (msdyn_notificationtemplate_*).
    param($Reference, $Schema)
    $pattern = [string]$Reference.columns
    if ($pattern.EndsWith('*')) {
        $prefix = $pattern.TrimEnd('*')
        return @($Schema.Attributes.Keys | Where-Object { $_.StartsWith($prefix) -and $Schema.Attributes[$_].Type -in 'String', 'Memo' } | Sort-Object)
    }
    if ($Schema.Attributes.ContainsKey($pattern)) { return @($pattern) }
    return @()
}

function Get-CcTableLabel {
    param($Table)
    if ($Table.label) { return $Table.label }
    return $Table.logicalName
}

function Get-CcColumnLabel {
    param($TablePlan, [string] $Column)
    $bare = $Column -replace '^_' -replace '_value$'
    if ($TablePlan -and $TablePlan.SourceSchema -and $TablePlan.SourceSchema.Attributes -and $TablePlan.SourceSchema.Attributes.ContainsKey($bare)) {
        return $TablePlan.SourceSchema.Attributes[$bare].Label
    }
    return $bare
}
