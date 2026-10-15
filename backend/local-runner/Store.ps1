# Profile store for the local runner. One folder per profile (one per client, typically), outside
# the repo, so a client's URLs and secrets never end up in a commit:
#
#   Windows:  %LOCALAPPDATA%\CcAlm\<profile>\registry.json   + runs\
#   other:    ~/.ccalm/<profile>/registry.json                + runs/
#
# Secrets are encrypted with Windows DPAPI (ConvertFrom-SecureString), so the file is only readable
# by the same Windows user on the same machine. Off Windows there is no DPAPI: secrets are kept in
# memory for the session only and have to be re-entered after a restart.

$script:CcSessionSecrets = @{}

function Initialize-CcStore([string] $ProfileName) {
    if ($ProfileName -notmatch '^[A-Za-z0-9_-]{1,40}$') {
        throw "Profile name '$ProfileName' must be 1-40 letters, digits, - or _."
    }
    $root = if ($IsWindows) { Join-Path $env:LOCALAPPDATA 'CcAlm' } else { Join-Path $HOME '.ccalm' }
    $script:CcStoreDir = Join-Path $root $ProfileName
    $script:CcRunsDir = Join-Path $script:CcStoreDir 'runs'
    $script:CcRegistryPath = Join-Path $script:CcStoreDir 'registry.json'
    $script:CcProfileName = $ProfileName
    New-Item -ItemType Directory -Path $script:CcRunsDir -Force | Out-Null
}

function Get-CcSecretStorage { if ($IsWindows) { 'dpapi' } else { 'session' } }

function Read-CcStore {
    if (-not (Test-Path $script:CcRegistryPath)) {
        return [pscustomobject]@{ version = 1; apiVersion = 'v9.2'; environments = @() }
    }
    $store = Get-Content $script:CcRegistryPath -Raw | ConvertFrom-Json
    $store.environments = @($store.environments)
    return $store
}

function Write-CcStore($store) {
    $store.environments = @($store.environments)
    $store | ConvertTo-Json -Depth 20 | Set-Content -Path $script:CcRegistryPath -Encoding UTF8
}

function Protect-CcSecret([string] $envId, [string] $plain) {
    if (-not $IsWindows) {
        $script:CcSessionSecrets[$envId] = $plain
        return $null
    }
    return (ConvertTo-SecureString $plain -AsPlainText -Force | ConvertFrom-SecureString)
}

function Unprotect-CcSecret($entry) {
    if (-not $IsWindows) { return $script:CcSessionSecrets[$entry.id] }
    if (-not $entry.secretProtected) { return $null }
    try {
        return (ConvertTo-SecureString $entry.secretProtected | ConvertFrom-SecureString -AsPlainText)
    }
    catch {
        # Encrypted by another Windows user or machine. Treat as missing so the wizard asks again.
        return $null
    }
}

function Test-CcHasSecret($entry) { return [bool](Unprotect-CcSecret $entry) }

function Test-CcReady($entry) {
    # Ready means every check has run since the last change and none failed.
    if (-not $entry.checks) { return $false }
    foreach ($c in Get-CcCheckDefinitions) {
        $r = $entry.checks.($c.id)
        if (-not $r -or $r.status -notin 'pass', 'warn') { return $false }
    }
    return $true
}

function Get-CcEngineRegistry([string[]] $EnvironmentId) {
    # The registry shape Connect-CcEnvironment takes, with secrets decrypted in memory only.
    $store = Read-CcStore
    $envs = foreach ($e in $store.environments) {
        if ($EnvironmentId -and $EnvironmentId -notcontains $e.id) { continue }
        $secret = Unprotect-CcSecret $e
        if (-not $secret) { throw "No saved secret for $($e.name). Open Setup and enter it again." }
        [pscustomobject]@{
            id = $e.id; name = $e.name; url = $e.url
            tenantId = $e.tenantId; clientId = $e.clientId; clientSecret = $secret
            role = $e.role; requireApproval = [bool]$e.requireApproval
        }
    }
    return [pscustomobject]@{ apiVersion = $store.apiVersion; environments = @($envs) }
}

function Save-CcRunRecord([string] $runId, $record) {
    $record | ConvertTo-Json -Depth 40 | Set-Content -Path (Join-Path $script:CcRunsDir "run-$runId.json") -Encoding UTF8
}

function Get-CcRunRecord([string] $runId) {
    if ($runId -notmatch '^[A-Za-z0-9_-]+$') { return $null }
    $path = Join-Path $script:CcRunsDir "run-$runId.json"
    if (-not (Test-Path $path)) { return $null }
    return (Get-Content $path -Raw | ConvertFrom-Json)
}
