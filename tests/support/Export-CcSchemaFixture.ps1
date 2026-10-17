<#
.SYNOPSIS
    Writes tests/fixtures/schema.json, the table metadata the synthetic test scenario runs on, from a
    recording's metadata (scripts/record-fixture.ps1).
.DESCRIPTION
    Keeps only what the engine reads from EntityDefinitions. The result is Microsoft's own schema
    for the Contact Center tables, with no records in it, so unlike a recording it is committed.
    Refresh it when a Dynamics release changes those tables.
.EXAMPLE
    ./tests/support/Export-CcSchemaFixture.ps1 -From tests/fixtures/recorded/dev-test/source.metadata.json
#>
#Requires -Version 7.2
param([Parameter(Mandatory)] [string] $From)

$ErrorActionPreference = 'Stop'
$label = { param($l) if ($l -and $l.UserLocalizedLabel) { @{ UserLocalizedLabel = @{ Label = $l.UserLocalizedLabel.Label } } } else { $null } }
$raw = Get-Content $From -Raw | ConvertFrom-Json -AsHashtable
$out = [ordered]@{}
foreach ($logical in ($raw.Keys | Sort-Object)) {
    $m = $raw[$logical]
    if (-not $m) { $out[$logical] = $null; continue }
    $out[$logical] = [ordered]@{
        LogicalName            = $m.LogicalName
        EntitySetName          = $m.EntitySetName
        PrimaryIdAttribute     = $m.PrimaryIdAttribute
        PrimaryNameAttribute   = $m.PrimaryNameAttribute
        DisplayCollectionName  = & $label $m.DisplayCollectionName
        Attributes             = @($m.Attributes | Sort-Object { $_.LogicalName } | ForEach-Object {
                [ordered]@{
                    LogicalName      = $_.LogicalName
                    AttributeType    = $_.AttributeType
                    AttributeOf      = $_.AttributeOf
                    IsValidForCreate = $_.IsValidForCreate
                    IsValidForRead   = $_.IsValidForRead
                    IsValidForUpdate = $_.IsValidForUpdate
                    RequiredLevel    = @{ Value = $_.RequiredLevel.Value }
                    DisplayName      = & $label $_.DisplayName
                }
            })
        ManyToOneRelationships = @($m.ManyToOneRelationships | Sort-Object { $_.ReferencingAttribute }, { $_.ReferencedEntity } | ForEach-Object {
                [ordered]@{
                    ReferencingAttribute                    = $_.ReferencingAttribute
                    ReferencedEntity                        = $_.ReferencedEntity
                    ReferencingEntityNavigationPropertyName = $_.ReferencingEntityNavigationPropertyName
                }
            })
    }
}
$path = Join-Path $PSScriptRoot '../fixtures/schema.json'
$out | ConvertTo-Json -Depth 20 | Set-Content $path -Encoding utf8NoBOM
Write-Host "Wrote $((Resolve-Path $path).Path) ($([math]::Round((Get-Item $path).Length / 1KB)) KB)."
