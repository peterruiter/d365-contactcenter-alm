function Export-CcReadCache {
    <#
    .SYNOPSIS
        Writes a read cache (New-CcReadCache) to a JSON file, for a later plan check or run.
        It holds the configuration records of both environments: keep it with the run records,
        never in a repo.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [pscustomobject] $Cache,
        [Parameter(Mandatory)] [string] $Path
    )
    $dir = Split-Path $Path -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [ordered]@{ version = $Cache.version; takenAt = $Cache.takenAt; entries = $Cache.entries } |
        ConvertTo-Json -Depth 50 -Compress | Set-Content -Path $Path -Encoding utf8NoBOM
}
