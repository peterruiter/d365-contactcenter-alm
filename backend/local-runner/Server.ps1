# The local runner's HTTP server. Serves the built app (app/dist-runner) and the same API the Azure
# Function exposes, plus /api/setup for the wizard, on http://localhost:<port> only.
#
# Every /api call must carry X-CcAlm-Local: 1. A browser cannot add a custom header to a cross-site
# request without a CORS preflight, which this server never answers - so another website open in
# the same browser cannot drive compare or apply against a client's environments.

function Get-CcManifestPathForRunner { $env:CCALM_MANIFEST_PATH }

function Send-CcResponse($ctx, [int] $status, [byte[]] $bytes, [string] $contentType) {
    $res = $ctx.Response
    $res.StatusCode = $status
    $res.ContentType = $contentType
    $res.Headers['Cache-Control'] = 'no-store'
    $res.Headers['X-Content-Type-Options'] = 'nosniff'
    $res.ContentLength64 = $bytes.Length
    $res.OutputStream.Write($bytes, 0, $bytes.Length)
}

function Send-CcJson($ctx, [int] $status, $body) {
    $json = ConvertTo-Json -InputObject $body -Depth 40
    Send-CcResponse $ctx $status ([Text.Encoding]::UTF8.GetBytes($json)) 'application/json; charset=utf-8'
}

function Send-CcError($ctx, [int] $status, [string] $code, [string] $message) {
    Send-CcJson $ctx $status @{ error = @{ code = $code; message = $message; details = @() } }
}

function Read-CcRequestBody($ctx) {
    $reader = [IO.StreamReader]::new($ctx.Request.InputStream, [Text.Encoding]::UTF8)
    try { $text = $reader.ReadToEnd() } finally { $reader.Dispose() }
    if ([string]::IsNullOrWhiteSpace($text)) { return [pscustomobject]@{} }
    return ($text | ConvertFrom-Json -Depth 40)
}

# --- Static files --------------------------------------------------------------------------------

$script:CcMimeTypes = @{
    '.html' = 'text/html; charset=utf-8'; '.js' = 'text/javascript; charset=utf-8'; '.css' = 'text/css; charset=utf-8'
    '.svg' = 'image/svg+xml'; '.png' = 'image/png'; '.ico' = 'image/x-icon'; '.json' = 'application/json'
    '.woff' = 'font/woff'; '.woff2' = 'font/woff2'; '.map' = 'application/json'
}

function Send-CcStatic($ctx, [string] $staticDir, [string] $path) {
    $index = Join-Path $staticDir 'index.html'
    if (-not (Test-Path $index)) {
        $msg = "The app is not built yet. Run: cd app; npm run build:runner  (or start scripts/run-local.ps1, which builds it)."
        Send-CcResponse $ctx 503 ([Text.Encoding]::UTF8.GetBytes($msg)) 'text/plain; charset=utf-8'
        return
    }
    $rel = [Uri]::UnescapeDataString($path.TrimStart('/'))
    $file = if ($rel) { [IO.Path]::GetFullPath((Join-Path $staticDir $rel)) } else { $index }
    # No path traversal out of the static folder; unknown paths fall back to the SPA.
    if (-not $file.StartsWith($staticDir, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path $file -PathType Leaf)) {
        $file = $index
    }
    $type = $script:CcMimeTypes[[IO.Path]::GetExtension($file).ToLowerInvariant()]
    if (-not $type) { $type = 'application/octet-stream' }
    Send-CcResponse $ctx 200 ([IO.File]::ReadAllBytes($file)) $type
}

# --- Setup ---------------------------------------------------------------------------------------

function ConvertTo-CcSetupView($entry) {
    [ordered]@{
        id              = $entry.id
        name            = $entry.name
        url             = $entry.url
        tenantId        = $entry.tenantId
        clientId        = $entry.clientId
        hasSecret       = Test-CcHasSecret $entry
        role            = if ($entry.role) { $entry.role } else { 'any' }
        requireApproval = [bool]$entry.requireApproval
        checks          = if ($entry.checks) { $entry.checks } else { @{} }
        ready           = Test-CcReady $entry
    }
}

function Get-CcSetupState {
    $store = Read-CcStore
    [ordered]@{
        profile       = $script:CcProfileName
        storePath     = $script:CcStoreDir
        secretStorage = Get-CcSecretStorage
        checks        = @(Get-CcCheckDefinitions)
        environments  = @($store.environments | ForEach-Object { ConvertTo-CcSetupView $_ })
    }
}

function Save-CcSetupEnvironment([string] $id, $body) {
    if ($id -notmatch '^[a-z0-9][a-z0-9-]{0,39}$') { throw [ArgumentException]'Environment id must be lowercase letters, digits and dashes.' }
    $name = ([string]$body.name).Trim()
    $url = ([string]$body.url).Trim().TrimEnd('/')
    $tenantId = ([string]$body.tenantId).Trim()
    $clientId = ([string]$body.clientId).Trim()
    if (-not $name) { throw [ArgumentException]'Name is required.' }
    if ($url -notmatch '^https://[A-Za-z0-9.-]+$') { throw [ArgumentException]'Environment URL must look like https://contoso-dev.crm4.dynamics.com (no path).' }
    if (-not $tenantId) { throw [ArgumentException]'Tenant ID is required.' }
    if ($clientId -notmatch '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') { throw [ArgumentException]'Client ID must be a GUID (Application (client) ID on the app registration Overview page).' }
    $role = if ($body.role -in 'any', 'source', 'target') { $body.role } else { 'any' }

    $store = Read-CcStore
    $entry = $store.environments | Where-Object id -eq $id | Select-Object -First 1
    $isNew = -not $entry
    if ($isNew) {
        $entry = [pscustomobject]@{ id = $id; name = $null; url = $null; tenantId = $null; clientId = $null; secretProtected = $null; role = 'any'; requireApproval = $false; checks = [pscustomobject]@{} }
        $store.environments = @($store.environments) + $entry
    }

    $changed = $isNew -or $entry.url -ne $url -or $entry.tenantId -ne $tenantId -or $entry.clientId -ne $clientId

    if ($body.clientSecret) {
        $entry.secretProtected = Protect-CcSecret $id ([string]$body.clientSecret)
        $changed = $true
    }
    elseif ($body.secretFrom) {
        $from = $store.environments | Where-Object id -eq $body.secretFrom | Select-Object -First 1
        if (-not $from -or -not (Test-CcHasSecret $from)) { throw [ArgumentException]"'$($body.secretFrom)' has no saved secret to copy." }
        # A DPAPI blob is reusable as-is for the same Windows user.
        $entry.secretProtected = $from.secretProtected
        if (-not $IsWindows) { $script:CcSessionSecrets[$id] = $script:CcSessionSecrets[$from.id] }
        $changed = $true
    }
    elseif (-not (Test-CcHasSecret $entry)) {
        throw [ArgumentException]'Client secret is required.'
    }

    $entry.name = $name; $entry.url = $url; $entry.tenantId = $tenantId; $entry.clientId = $clientId
    $entry.role = $role; $entry.requireApproval = [bool]$body.requireApproval
    # New credentials or a new URL invalidate every earlier check result.
    if ($changed) { $entry.checks = [pscustomobject]@{} }

    Write-CcStore $store
    return ConvertTo-CcSetupView $entry
}

function Invoke-CcSetupCheck([string] $id, [string] $checkId) {
    $store = Read-CcStore
    $entry = $store.environments | Where-Object id -eq $id | Select-Object -First 1
    if (-not $entry) { return $null }
    $defs = @(Get-CcCheckDefinitions)
    $pos = [array]::IndexOf(@($defs.id), $checkId)
    if ($pos -lt 0) { throw [ArgumentException]"Unknown check '$checkId'." }

    $secret = Unprotect-CcSecret $entry
    $result = if (-not $secret) {
        New-CcCheckResult 'fail' 'No saved secret.' @() 'Enter the client secret again in the details step.'
    }
    else {
        try { Invoke-CcCheck $checkId $entry $secret }
        catch { New-CcCheckResult 'fail' 'The check itself crashed.' @($_.Exception.Message) 'This is a bug in the runner, not the setup. The detail above says where.' }
    }

    if (-not $entry.checks) { $entry.checks = [pscustomobject]@{} }
    $entry.checks | Add-Member -NotePropertyName $checkId -NotePropertyValue ([pscustomobject]$result) -Force
    # Anything after this check was judged against the old state; drop it so it runs again.
    foreach ($later in $defs | Select-Object -Skip ($pos + 1)) {
        $entry.checks.PSObject.Properties.Remove($later.id)
    }
    Write-CcStore $store
    return ConvertTo-CcSetupView $entry
}

# --- Engine routes (same contract as the Azure Function) -----------------------------------------

function Get-CcRunnerEnvironments([string[]] $ids) {
    Connect-CcEnvironment -Registry (Get-CcEngineRegistry $ids) -EnvironmentId $ids -SkipCheck
}

function Get-CcSelection($body) {
    if ($body.selection) { return @($body.selection | ForEach-Object { @{ table = $_.table; matchKey = $_.matchKey } }) }
    return $null
}

function Invoke-CcApiRoute($ctx, [string] $method, [string] $path) {
    switch -Regex ("$method $path") {
        '^GET /api/environments$' {
            $ready = @((Read-CcStore).environments | Where-Object { Test-CcReady $_ } | ForEach-Object {
                    [ordered]@{ id = $_.id; name = $_.name; url = $_.url; role = $(if ($_.role) { $_.role } else { 'any' }); requireApproval = [bool]$_.requireApproval }
                })
            return Send-CcJson $ctx 200 $ready
        }
        '^POST /api/(compare|plan|apply)$' {
            $op = $Matches[1]
            $body = Read-CcRequestBody $ctx
            if (-not $body.sourceEnvId -or -not $body.targetEnvId) { return Send-CcError $ctx 400 'bad_request' 'sourceEnvId and targetEnvId are required.' }
            $envs = Get-CcRunnerEnvironments @($body.sourceEnvId, $body.targetEnvId)
            $tables = if ($op -eq 'compare' -and $body.tables) { @($body.tables) } else { $null }
            $diff = Compare-CcConfig -Environments $envs -SourceId $body.sourceEnvId -TargetId $body.targetEnvId -Tables $tables
            if ($op -eq 'compare') { return Send-CcJson $ctx 200 (ConvertTo-CcDiffContract $diff) }

            $plan = New-CcPlan -Diff $diff -Selection (Get-CcSelection $body)
            if ($op -eq 'plan') { return Send-CcJson $ctx 200 (ConvertTo-CcPlanContract $plan) }

            if ($plan.operations.Count -eq 0) {
                return Send-CcJson $ctx 200 @{ runId = 'run_noop'; mode = $body.mode; target = $body.targetEnvId; state = 'Succeeded'; snapshotId = $null; stages = @(); problems = @() }
            }
            $mode = if ($body.mode -eq 'apply') { 'Apply' } else { 'DryRun' }
            $outDir = Join-Path $script:CcRunsDir "work-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
            New-Item -ItemType Directory -Path $outDir | Out-Null
            try {
                $run = Invoke-CcPlan -Plan $plan -Environments $envs -Mode $mode -Approved:([bool]$body.approved) -OutputDir $outDir
                $snapshotId = $null
                if ($mode -eq 'Apply' -and $run.snapshot -and (Test-Path $run.snapshot)) {
                    Copy-Item $run.snapshot (Join-Path $script:CcRunsDir "snapshot-$($run.runId).json")
                    $snapshotId = $run.runId
                }
                $contract = ConvertTo-CcRunContract $run $snapshotId
                Save-CcRunRecord $run.runId $contract
                return Send-CcJson $ctx 200 $contract
            }
            finally { Remove-Item $outDir -Recurse -Force -ErrorAction SilentlyContinue }
        }
        '^GET /api/run/([A-Za-z0-9_-]+)$' {
            $run = Get-CcRunRecord $Matches[1]
            if (-not $run) { return Send-CcError $ctx 404 'not_found' "Run $($Matches[1]) not found." }
            return Send-CcJson $ctx 200 $run
        }
        '^POST /api/run/([A-Za-z0-9_-]+)/rollback$' {
            $id = $Matches[1]
            $run = Get-CcRunRecord $id
            if (-not $run) { return Send-CcError $ctx 404 'not_found' "Run $id not found." }
            if (-not $run.snapshotId) { return Send-CcError $ctx 400 'no_snapshot' 'This run has no snapshot. A dry run cannot be rolled back.' }
            $snapshot = Join-Path $script:CcRunsDir "snapshot-$id.json"
            $envs = Get-CcRunnerEnvironments @($run.target)
            $result = Restore-CcRun -SnapshotPath $snapshot -Environments $envs -Confirm:$false
            $run.state = 'RolledBack'
            Save-CcRunRecord $id $run
            return Send-CcJson $ctx 200 ([ordered]@{
                    runId = $id; state = 'RolledBack'; mode = $run.mode; target = $run.target; snapshotId = $run.snapshotId
                    stages = @($run.stages); problems = @($run.problems)
                    cleanup = @{ restored = $result.restored; unresolved = @($result.unresolved) }
                })
        }
        '^GET /api/setup$' {
            return Send-CcJson $ctx 200 (Get-CcSetupState)
        }
        '^PUT /api/setup/environments/([a-z0-9-]+)$' {
            $id = $Matches[1]
            return Send-CcJson $ctx 200 (Save-CcSetupEnvironment $id (Read-CcRequestBody $ctx))
        }
        '^DELETE /api/setup/environments/([a-z0-9-]+)$' {
            $id = $Matches[1]
            $store = Read-CcStore
            $store.environments = @($store.environments | Where-Object id -ne $id)
            Write-CcStore $store
            $script:CcSessionSecrets.Remove($id)
            return Send-CcJson $ctx 200 @{ deleted = $id }
        }
        '^POST /api/setup/environments/([a-z0-9-]+)/checks/([a-z]+)$' {
            $view = Invoke-CcSetupCheck $Matches[1] $Matches[2]
            if (-not $view) { return Send-CcError $ctx 404 'not_found' "Environment $($Matches[1]) not found." }
            return Send-CcJson $ctx 200 $view
        }
        default { return Send-CcError $ctx 404 'not_found' "No route for $method $path." }
    }
}

# --- Loop ----------------------------------------------------------------------------------------

function Start-CcLocalRunner([int] $Port, [string] $StaticDir, [switch] $OpenBrowser) {
    $origin = "http://localhost:$Port"
    # Vite's dev server (npm run dev:runner) proxies /api here from port 3000.
    $allowedOrigins = @($origin, 'http://localhost:3000')

    $listener = [Net.HttpListener]::new()
    $listener.Prefixes.Add("$origin/")
    $listener.Start()
    Write-Host "Contact Center ALM local runner: $origin  (profile '$script:CcProfileName', Ctrl+C to stop)" -ForegroundColor Green
    if ($OpenBrowser) { Start-Process "$origin/" }

    try {
        while ($listener.IsListening) {
            $task = $listener.GetContextAsync()
            # Short waits so Ctrl+C is honoured between them.
            while (-not $task.Wait(250)) { }
            $ctx = $task.Result
            $req = $ctx.Request
            $path = $req.Url.AbsolutePath
            $sw = [Diagnostics.Stopwatch]::StartNew()
            try {
                if ($path.StartsWith('/api/')) {
                    $reqOrigin = $req.Headers['Origin']
                    if ($req.Headers['X-CcAlm-Local'] -ne '1' -or ($reqOrigin -and $allowedOrigins -notcontains $reqOrigin)) {
                        Send-CcError $ctx 403 'forbidden' 'Requests must come from the runner app.'
                    }
                    else {
                        Invoke-CcApiRoute $ctx $req.HttpMethod $path
                    }
                }
                else {
                    Send-CcStatic $ctx $StaticDir $path
                }
            }
            catch {
                # Validation errors carry a message meant for the user; anything else gets the full
                # text with location, like the Function returns.
                if ($_.Exception -is [ArgumentException]) { $status = 400; $code = 'bad_request'; $msg = $_.Exception.Message }
                else { $status = 500; $code = 'runner_failed'; $msg = Get-CcErrorText $_ }
                try { Send-CcError $ctx $status $code $msg } catch { }
            }
            finally {
                if ($path.StartsWith('/api/')) {
                    Write-Host ("{0:HH:mm:ss} {1,-6} {2} -> {3} ({4} ms)" -f (Get-Date), $req.HttpMethod, $path, $ctx.Response.StatusCode, $sw.ElapsedMilliseconds)
                }
                try { $ctx.Response.Close() } catch { }
            }
        }
    }
    finally {
        $listener.Stop()
        $listener.Close()
        Write-Host 'Local runner stopped.'
    }
}
