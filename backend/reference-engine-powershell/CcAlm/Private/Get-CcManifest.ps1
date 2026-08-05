function Get-CcManifest {
    <#
    .SYNOPSIS
        Loads the table manifest and returns it sorted by write order.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path
    )

    if (-not (Test-Path $Path)) { throw "Manifest not found at $Path" }

    $manifest = Get-Content -Path $Path -Raw | ConvertFrom-Json
    if (-not $manifest.tables) { throw "Manifest has no tables array." }

    $manifest.tables = @($manifest.tables | Sort-Object order)

    # Cheap sanity checks so a bad manifest fails at load, not mid-run.
    foreach ($t in $manifest.tables) {
        if (-not $t.logicalName) { throw "Manifest table missing logicalName (order $($t.order))." }
        if (-not $t.entitySet)   { throw "Manifest table $($t.logicalName) missing entitySet." }
        if (-not $t.matchKeys -or $t.matchKeys.Count -eq 0) {
            throw "Manifest table $($t.logicalName) has no matchKeys."
        }
    }

    return $manifest
}
