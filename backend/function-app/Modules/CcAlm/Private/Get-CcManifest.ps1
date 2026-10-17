function Get-CcManifest {
    <#
    .SYNOPSIS
        Loads the table manifest, sorted by write order, and checks it is one this engine reads.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path
    )

    if (-not (Test-Path $Path)) { throw "Manifest not found at $Path" }
    $manifest = Get-Content -Path $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $manifest.tables) { throw "Manifest has no tables array." }
    if (-not ([string]$manifest.version).StartsWith('2.')) {
        throw "Manifest version $($manifest.version) is not supported. This engine reads version 2 manifests (columns come from metadata)."
    }

    $manifest.tables = @($manifest.tables | Sort-Object { [int]$_.order })
    $moves = 'upsert', 'create-once', 'update-only', 'reference', 'detect'
    foreach ($t in $manifest.tables) {
        if (-not $t.logicalName) { throw "Manifest table missing logicalName (order $($t.order))." }
        if ($moves -notcontains $t.move) { throw "Manifest table $($t.logicalName) has move '$($t.move)'; expected one of $($moves -join ', ')." }
        if (-not $t.matchKeys -or @($t.matchKeys).Count -eq 0) { throw "Manifest table $($t.logicalName) has no matchKeys." }
    }
    return $manifest
}

function Get-CcStageLabel {
    param($Manifest, [int] $Stage)
    if ($Stage -eq 99) { return 'Link records written earlier' }
    $s = @($Manifest.stages) | Where-Object { [int]$_.stage -eq $Stage } | Select-Object -First 1
    if ($s) { return $s.label }
    return "Stage $Stage"
}
