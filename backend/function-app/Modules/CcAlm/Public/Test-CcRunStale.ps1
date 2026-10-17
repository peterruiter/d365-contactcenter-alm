function Test-CcRunStale {
    <#
    .SYNOPSIS
        True when a run says it is in progress but has not saved anything for a while: the worker
        holding it stopped (a restart, a crash, the 10-minute limit). The app then offers to continue.
    #>
    param($Run, [int] $Minutes = 12)
    if ($Run.state -notin 'Queued', 'Running', 'RollingBack') { return $false }
    # ConvertFrom-Json in PowerShell 7 already turns an ISO date into a DateTime; a string (from
    # another reader) is parsed as the ISO round-trip format it was written in, never by culture.
    $value = $Run.updatedAt
    $at = $null
    if ($value -is [datetime]) { $at = $value }
    elseif ($value -is [datetimeoffset]) { $at = $value.LocalDateTime }
    else {
        $parsed = [datetimeoffset]::MinValue
        if ([datetimeoffset]::TryParse([string]$value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind, [ref]$parsed)) { $at = $parsed.LocalDateTime }
    }
    if (-not $at) { return $false }   # unknown age: never call a run stale on a guess
    return ((Get-Date) - $at).TotalMinutes -gt $Minutes
}
