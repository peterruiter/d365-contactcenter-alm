# Runs once on cold start. Loads the engine and defines helpers shared by every function.

$ErrorActionPreference = 'Stop'

Import-Module "$PSScriptRoot/Modules/CcAlm/CcAlm.psd1" -Force

# The manifest ships beside the function app (deploy copies it here).
if (Test-Path "$PSScriptRoot/manifest.json") {
    $env:CCALM_MANIFEST_PATH = "$PSScriptRoot/manifest.json"
}

# Labels, contract mappers and error text, shared with the local runner.
. "$PSScriptRoot/Contract.ps1"

# --- Connect using app settings, not a file ------------------------------------

function Get-CcRegistryJson {
    # The registry can come from the CCALM_ENVIRONMENTS app setting, or from an environments.json
    # shipped with the app. The file fallback avoids CLI quoting problems when setting a big JSON
    # blob as an app setting.
    if ($env:CCALM_ENVIRONMENTS) { return $env:CCALM_ENVIRONMENTS }
    $file = Join-Path $PSScriptRoot 'environments.json'
    if (Test-Path $file) { return (Get-Content $file -Raw) }
    throw 'No environment registry. Set CCALM_ENVIRONMENTS, or ship environments.json with the app.'
}

function Get-CcConnected([string[]] $Ids) {
    # Only the environments a request needs: one unreachable environment elsewhere in the registry
    # must not stop a compare or a run between two others.
    $json = Get-CcRegistryJson
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "ccalm-env-$([guid]::NewGuid().ToString('N')).json"
    Set-Content -Path $tmp -Value $json -Encoding UTF8
    try {
        if ($Ids) { return Connect-CcEnvironment -ConfigPath $tmp -EnvironmentId $Ids -SkipCheck }
        return Connect-CcEnvironment -ConfigPath $tmp
    }
    finally {
        Remove-Item $tmp -ErrorAction SilentlyContinue
    }
}

# --- Blob persistence for run records and snapshots ----------------------------

function Get-CcBlobContext {
    if (-not $env:AzureWebJobsStorage) { throw 'AzureWebJobsStorage is not set.' }
    New-AzStorageContext -ConnectionString $env:AzureWebJobsStorage
}

function Get-CcRunsContainer {
    if ($env:CCALM_RUNS_CONTAINER) { return $env:CCALM_RUNS_CONTAINER }
    return 'ccalm-runs'
}

function Confirm-CcRunsContainer {
    # Idempotent: create the runs container the first time anything writes to it.
    $ctx = Get-CcBlobContext
    $container = Get-CcRunsContainer
    if (-not (Get-AzStorageContainer -Name $container -Context $ctx -ErrorAction SilentlyContinue)) {
        New-AzStorageContainer -Name $container -Context $ctx -Permission Off | Out-Null
    }
    return $container
}

function Save-CcBlobJson([string] $name, $object) {
    $ctx = Get-CcBlobContext
    $container = Confirm-CcRunsContainer
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) $name
    $object | ConvertTo-Json -Depth 40 | Set-Content -Path $tmp -Encoding UTF8
    Set-AzStorageBlobContent -File $tmp -Container $container -Blob $name -Context $ctx -Force | Out-Null
    Remove-Item $tmp -ErrorAction SilentlyContinue
}

function Get-CcBlobJson([string] $name) {
    $ctx = Get-CcBlobContext
    $container = Get-CcRunsContainer
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) $name
    Get-AzStorageBlobContent -Blob $name -Container $container -Destination $tmp -Context $ctx -Force -ErrorAction Stop | Out-Null
    $json = Get-Content -Path $tmp -Raw | ConvertFrom-Json
    Remove-Item $tmp -ErrorAction SilentlyContinue
    return $json
}

function Get-CcBlobFile([string] $name, [string] $destination) {
    $ctx = Get-CcBlobContext
    $container = Get-CcRunsContainer
    Get-AzStorageBlobContent -Blob $name -Container $container -Destination $destination -Context $ctx -Force -ErrorAction Stop | Out-Null
    return $destination
}

# --- HTTP helpers --------------------------------------------------------------

function Read-CcBody($Request) {
    if ($Request.Body -is [string]) {
        if ([string]::IsNullOrWhiteSpace($Request.Body)) { return @{} }
        return $Request.Body | ConvertFrom-Json
    }
    return $Request.Body
}

function Push-CcJson([int] $status, $body) {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode  = $status
        Headers     = @{ 'Content-Type' = 'application/json' }
        Body        = ($body | ConvertTo-Json -Depth 40)
    })
}

function Push-CcError([int] $status, [string] $code, [string] $message) {
    Push-CcJson $status @{ error = @{ code = $code; message = $message; details = @() } }
}
