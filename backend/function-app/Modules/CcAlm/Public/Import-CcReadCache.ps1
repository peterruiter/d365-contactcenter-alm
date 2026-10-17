function Import-CcReadCache {
    <#
    .SYNOPSIS
        Reads a cache written by Export-CcReadCache. Returns $null when the file is missing,
        unreadable, or older than -MaxAgeMinutes, so the caller simply reads Dataverse again.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [int] $MaxAgeMinutes = 60
    )
    if (-not (Test-Path $Path)) { return $null }
    try {
        # Parsed the same way Invoke-RestMethod parses a response, so replayed reads look exactly
        # like live ones (records as PSCustomObjects, dates as DateTime).
        $raw = Get-Content -Path $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch { return $null }
    if (-not $raw -or [int]$raw.version -ne 1 -or -not $raw.entries) { return $null }

    $taken = if ($raw.takenAt -is [datetime]) { $raw.takenAt } else { [datetime]::Parse([string]$raw.takenAt, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind) }
    if (((Get-Date) - $taken).TotalMinutes -gt $MaxAgeMinutes) { return $null }

    $entries = @{}
    foreach ($p in $raw.entries.PSObject.Properties) { $entries[$p.Name] = $p.Value }
    [pscustomobject]@{ version = 1; takenAt = $taken.ToString('o'); entries = $entries }
}
