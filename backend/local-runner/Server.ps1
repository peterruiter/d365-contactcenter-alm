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

$script:CcDiffCache = @{}
$script:CcJobs = @{}

# Runs in its own runspace, so a long apply never blocks the server: the app keeps polling GetRun
# while records are written. Progress and the rollback snapshot go to the run's files as it goes.
$script:CcJobScript = {
    param($ModulePath, $ManifestPath, $Registry, $RunsDir, $RunId, $Kind)
    $ErrorActionPreference = 'Stop'
    $env:CCALM_MANIFEST_PATH = $ManifestPath
    Import-Module $ModulePath -Force
    $runFile = Join-Path $RunsDir "run-$RunId.json"
    $snapFile = Join-Path $RunsDir "snapshot-$RunId.json"
    $load = {
        for ($i = 0; $i -lt 5; $i++) { try { return (Get-Content $runFile -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { Start-Sleep -Milliseconds 100 } }
        throw "Cannot read $runFile"
    }.GetNewClosure()
    $save = {
        param($r)
        $tmp = "$runFile.$([guid]::NewGuid().ToString('N')).tmp"
        $r | ConvertTo-Json -Depth 40 | Set-Content $tmp -Encoding UTF8
        Move-Item $tmp $runFile -Force
    }.GetNewClosure()
    $loadSnap = { if (Test-Path $snapFile) { Get-Content $snapFile -Raw -Encoding UTF8 | ConvertFrom-Json } }.GetNewClosure()
    $saveSnap = {
        param($s)
        $tmp = "$snapFile.tmp"
        $s | ConvertTo-Json -Depth 40 | Set-Content $tmp -Encoding UTF8
        Move-Item $tmp $snapFile -Force
    }.GetNewClosure()

    $run = & $load
    $envs = Connect-CcEnvironment -Registry $Registry -EnvironmentId @($run.source, $run.target) -SkipCheck
    if ($Kind -eq 'rollback') {
        Invoke-CcRollbackJob -Environments $envs -LoadRun $load -SaveRun $save -SnapshotPath $snapFile
        return
    }
    $work = Join-Path $RunsDir "work-$RunId"
    New-Item -ItemType Directory $work -Force | Out-Null
    try {
        Invoke-CcRunJob -Environments $envs -LoadRun $load -SaveRun $save -LoadSnapshot $loadSnap -SaveSnapshot $saveSnap -WorkDir $work -ManifestPath $ManifestPath | Out-Null
    }
    finally { Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue }
}

function Start-CcRunnerJob([string] $RunId, [string] $Kind, $Registry) {
    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    try { $iss.ExecutionPolicy = [Microsoft.PowerShell.ExecutionPolicy]::Bypass } catch { }
    $rs = [runspacefactory]::CreateRunspace($iss)
    $rs.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    $modulePath = Join-Path (Get-Module CcAlm).ModuleBase 'CcAlm.psd1'
    [void]$ps.AddScript($script:CcJobScript.ToString()).AddArgument($modulePath).AddArgument($env:CCALM_MANIFEST_PATH).AddArgument($Registry).AddArgument($script:CcRunsDir).AddArgument($RunId).AddArgument($Kind)
    $script:CcJobs[$RunId] = @{ PS = $ps; Handle = $ps.BeginInvoke(); Runspace = $rs }
}

function Update-CcRunnerJobs {
    # Collects finished background runs. One that ended without finishing its run record (an
    # exception before the engine could record it) is marked Failed with the reason.
    foreach ($id in @($script:CcJobs.Keys)) {
        $j = $script:CcJobs[$id]
        if (-not $j.Handle.IsCompleted) { continue }
        $err = $null
        try {
            [void]$j.PS.EndInvoke($j.Handle)
            if ($j.PS.Streams.Error.Count -gt 0) { $err = $j.PS.Streams.Error[0].ToString() }
        }
        catch { $err = $_.Exception.Message }
        $j.PS.Dispose()
        $j.Runspace.Dispose()
        $script:CcJobs.Remove($id)
        $run = Get-CcRunRecord $id
        if ($run -and $run.state -in 'Queued', 'Running', 'RollingBack') {
            $run = ConvertTo-CcRunHashtable $run
            $run.state = 'Failed'
            $run.phase = 'done'
            $run.message = if ($err) { $err } else { 'The run stopped unexpectedly.' }
            $run.updatedAt = (Get-Date).ToString('o')
            Save-CcRunRecord $id $run
        }
    }
}

function Get-CcLiveRun($run) {
    # A run that says it is busy but has no job here lost it: the runner was closed mid-run.
    if ($run -and $run.state -in 'Queued', 'Running', 'RollingBack' -and -not $script:CcJobs.ContainsKey($run.runId)) {
        $run = ConvertTo-CcRunHashtable $run
        $run.state = 'Interrupted'
        $run.phase = 'done'
        $run.message = 'This run stopped before it finished, because the local runner was closed. Continuing it compares again and writes only what is still missing.'
        Save-CcRunRecord $run.runId $run
    }
    return $run
}

function Set-CcCachedDiff($diff) {
    # One recent compare per source/target pair, for planning without reading both orgs again.
    $script:CcDiffCache["$($diff.source)|$($diff.target)"] = @{ Diff = $diff; At = Get-Date }
}

function Get-CcCachedDiff([string] $diffId, [string] $source, [string] $target) {
    $c = $script:CcDiffCache["$source|$target"]
    if ($c -and $c.Diff.diffId -eq $diffId -and $c.At -gt (Get-Date).AddMinutes(-30)) { return $c.Diff }
    return $null
}

function Get-CcSelection($body) {
    if ($body.selection) { return @($body.selection | ForEach-Object { @{ table = $_.table; matchKey = $_.matchKey } }) }
    return $null
}

# The latest local runner release on GitHub: the build.json the release script uploads next to the
# exe and the zip. Asked by the runner, not the browser (no CORS, no per-browser rate limit, and it
# goes through the machine's proxy), at most every six hours. CCALM_UPDATE_URL points a fork at
# its own release.
$script:CcReleasePage = 'https://github.com/peterruiter/d365-contactcenter-alm/releases/tag/localrunner'
$script:CcUpdateUrl = if ($env:CCALM_UPDATE_URL) { $env:CCALM_UPDATE_URL } else { 'https://github.com/peterruiter/d365-contactcenter-alm/releases/download/localrunner/build.json' }
$script:CcUpdate = $null

function Get-CcLatestRelease([switch] $Refresh) {
    $c = $script:CcUpdate
    if (-not $Refresh -and $c -and $c.At -gt (Get-Date).AddHours(-6)) { return $c.Info }
    $info = [ordered]@{ latest = $null; releaseUrl = $script:CcReleasePage; checkedAt = (Get-Date).ToString('o'); error = $null }
    try {
        $r = Invoke-WebRequest -Uri $script:CcUpdateUrl -TimeoutSec 8 -UseBasicParsing -ErrorAction Stop
        # Release assets come as application/octet-stream, so the body may arrive as bytes.
        $text = if ($r.Content -is [byte[]]) { [Text.Encoding]::UTF8.GetString($r.Content) } else { [string]$r.Content }
        $j = $text | ConvertFrom-Json
        $builtAt = if ($j.builtAt -is [datetime]) { $j.builtAt.ToUniversalTime().ToString('o') } else { [string]$j.builtAt }
        $info.latest = [ordered]@{ version = [string]$j.version; build = [int]$j.build; commit = [string]$j.commit; builtAt = $builtAt }
    }
    catch {
        # Offline, blocked by a proxy, or no build.json on the release yet: no update banner.
        $info.error = $_.Exception.Message
    }
    $script:CcUpdate = @{ Info = $info; At = Get-Date }
    return $info
}

function Invoke-CcApiRoute($ctx, [string] $method, [string] $path) {
    switch -Regex ("$method $path") {
        '^GET /api/update$' {
            return Send-CcJson $ctx 200 (Get-CcLatestRelease -Refresh:([bool]$ctx.Request.QueryString['refresh']))
        }
        '^GET /api/environments$' {
            $ready = @((Read-CcStore).environments | Where-Object { Test-CcReady $_ } | ForEach-Object {
                    [ordered]@{ id = $_.id; name = $_.name; url = $_.url; role = $(if ($_.role) { $_.role } else { 'any' }); requireApproval = [bool]$_.requireApproval }
                })
            return Send-CcJson $ctx 200 $ready
        }
        '^POST /api/apply$' {
            # Dry run or apply, in the background; the app polls GetRun.
            $body = Read-CcRequestBody $ctx
            if (-not $body.sourceEnvId -or -not $body.targetEnvId) { return Send-CcError $ctx 400 'bad_request' 'sourceEnvId and targetEnvId are required.' }
            $mode = if ($body.mode -eq 'apply') { 'apply' } else { 'dryRun' }
            $target = (Read-CcStore).environments | Where-Object id -eq $body.targetEnvId | Select-Object -First 1
            if (-not $target) { return Send-CcError $ctx 400 'bad_request' "Unknown target '$($body.targetEnvId)'." }
            if ($mode -eq 'apply' -and $target.requireApproval -and -not [bool]$body.approved) {
                return Send-CcError $ctx 400 'approval_required' "$($target.name) requires approval. Confirm the change has been signed off, then apply again."
            }
            $registry = Get-CcEngineRegistry @($body.sourceEnvId, $body.targetEnvId)
            $rec = New-CcRunRecord -SourceId $body.sourceEnvId -TargetId $body.targetEnvId -Mode $mode -Selection (Get-CcSelection $body) -Approved ([bool]$body.approved)
            Save-CcRunRecord $rec.runId $rec
            Start-CcRunnerJob $rec.runId 'apply' $registry
            return Send-CcJson $ctx 200 $rec
        }
        '^POST /api/(compare|plan)$' {
            $op = $Matches[1]
            $body = Read-CcRequestBody $ctx
            if (-not $body.sourceEnvId -or -not $body.targetEnvId) { return Send-CcError $ctx 400 'bad_request' 'sourceEnvId and targetEnvId are required.' }
            $envs = Get-CcRunnerEnvironments @($body.sourceEnvId, $body.targetEnvId)

            # Planning reuses the compare it was built from (instant, and exactly what the person
            # reviewed). Applying always reads both environments again, so it never writes from
            # a stale picture of the target.
            $diff = $null
            if ($op -eq 'plan' -and $body.diffId) { $diff = Get-CcCachedDiff $body.diffId $body.sourceEnvId $body.targetEnvId }
            if (-not $diff) {
                $tables = if ($op -eq 'compare' -and $body.tables) { @($body.tables) } else { $null }
                $diff = Compare-CcConfig -Environments $envs -SourceId $body.sourceEnvId -TargetId $body.targetEnvId -Tables $tables
                Set-CcCachedDiff $diff
            }
            if ($op -eq 'compare') { return Send-CcJson $ctx 200 (ConvertTo-CcDiffContract $diff) }

            if ($op -eq 'plan') {
                $includeDeps = if ($null -ne $body.includeDependencies) { [bool]$body.includeDependencies } else { $true }
                $plan = New-CcPlan -Diff $diff -Selection (Get-CcSelection $body) -IncludeDependencies $includeDeps
                return Send-CcJson $ctx 200 (ConvertTo-CcPlanContract $plan)
            }

        }
        '^GET /api/runs$' {
            # Recent runs, newest first, without their item lists.
            $runs = @(Get-ChildItem $script:CcRunsDir -Filter 'run-*.json' -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTime -Descending | Select-Object -First 25 | ForEach-Object {
                        $r = Get-CcLiveRun (Get-CcRunRecord ($_.BaseName -replace '^run-'))
                        if (-not $r) { return }
                        [ordered]@{ runId = $r.runId; mode = $r.mode; source = $r.source; target = $r.target; state = $r.state; startedAt = $r.startedAt; finishedAt = $r.finishedAt; summary = $r.summary; snapshotId = $r.snapshotId }
                    })
            return Send-CcJson $ctx 200 $runs
        }
        '^GET /api/run/([A-Za-z0-9_-]+)$' {
            $run = Get-CcLiveRun (Get-CcRunRecord $Matches[1])
            if (-not $run) { return Send-CcError $ctx 404 'not_found' "Run $($Matches[1]) not found." }
            return Send-CcJson $ctx 200 $run
        }
        '^POST /api/run/([A-Za-z0-9_-]+)/rollback$' {
            $id = $Matches[1]
            $run = Get-CcLiveRun (Get-CcRunRecord $id)
            if (-not $run) { return Send-CcError $ctx 404 'not_found' "Run $id not found." }
            if (-not $run.snapshotId) { return Send-CcError $ctx 400 'no_snapshot' 'This run has no snapshot. A dry run cannot be rolled back.' }
            if ($script:CcJobs.ContainsKey($id)) { return Send-CcError $ctx 409 'busy' 'This run is still in progress. Roll it back once it has finished.' }
            $registry = Get-CcEngineRegistry @($run.source, $run.target)
            $run = ConvertTo-CcRunHashtable $run
            $run.state = 'RollingBack'
            $run.phase = 'rollingBack'
            $run.progress.current = 'Waiting to start'
            $run.updatedAt = (Get-Date).ToString('o')
            Save-CcRunRecord $id $run
            Start-CcRunnerJob $id 'rollback' $registry
            return Send-CcJson $ctx 200 $run
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
            while (-not $task.Wait(250)) { Update-CcRunnerJobs }
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
