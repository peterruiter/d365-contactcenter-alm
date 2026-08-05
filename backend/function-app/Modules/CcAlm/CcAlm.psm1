Set-StrictMode -Version Latest
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
