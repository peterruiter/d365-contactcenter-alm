function Get-CcDefaultManifestPath {
    <#
    .SYNOPSIS
        Resolves the manifest location. Order: CCALM_MANIFEST_PATH env var, then a copy shipped next to
        the module (function app), then a walk up the tree to config/manifest.json (repo / CLI).
    #>
    [CmdletBinding()]
    param()

    if ($env:CCALM_MANIFEST_PATH -and (Test-Path $env:CCALM_MANIFEST_PATH)) {
        return $env:CCALM_MANIFEST_PATH
    }

    # A copy placed beside the module, e.g. in the deployed function app.
    $beside = Join-Path $PSScriptRoot '..' 'manifest.json'
    if (Test-Path $beside) { return (Resolve-Path $beside).Path }

    # Walk up looking for config/manifest.json (repo layout for the CLI).
    $dir = $PSScriptRoot
    for ($i = 0; $i -lt 8 -and $dir; $i++) {
        $candidate = Join-Path $dir 'config/manifest.json'
        if (Test-Path $candidate) { return (Resolve-Path $candidate).Path }
        $parent = Split-Path $dir -Parent
        if ($parent -eq $dir) { break }
        $dir = $parent
    }

    throw "Cannot find manifest.json. Set CCALM_MANIFEST_PATH or place config/manifest.json in the repo."
}
