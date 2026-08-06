# The manifest and the environment registry use optional properties by design (only some tables
# have skipColumns, guidBearingColumns, async, and so on; only some environments have
# requireApproval). Strict mode 'Latest' throws when reading a property that is absent, which
# fights that design. Off matches how the engine is validated. Errors still surface via
# ErrorActionPreference = Stop.
Set-StrictMode -Off
$ErrorActionPreference = 'Stop'

# Load private helpers first, then public cmdlets.
foreach ($folder in 'Private', 'Public') {
    $dir = Join-Path $PSScriptRoot $folder
    if (-not (Test-Path $dir)) { continue }
    Get-ChildItem -Path $dir -Filter '*.ps1' | ForEach-Object {
        . $_.FullName
    }
}

$public = Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public') -Filter '*.ps1' |
    ForEach-Object { $_.BaseName }

Export-ModuleMember -Function $public
