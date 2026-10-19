# Setup checks for one environment, run one at a time from the wizard. Each returns
#   status   pass | warn | fail
#   summary  one line for the check row
#   detail   lines with what was found
#   fix      what to do about a fail or warn, phrased for a consultant who can only ask the client
#            for things, not change Entra themselves
#
# They talk to Entra and Dataverse directly rather than through the engine, because they need the
# raw status codes and AADSTS error codes to say what is actually wrong.

$script:CcCheckTokens = @{}

function Get-CcCheckDefinitions {
    @(
        [ordered]@{ id = 'tenant';        title = 'Tenant';           description = 'The tenant ID belongs to a real Entra tenant.' }
        [ordered]@{ id = 'signin';        title = 'Sign in';          description = 'The client ID and secret sign in and get a token for this environment.' }
        [ordered]@{ id = 'appuser';       title = 'Application user'; description = 'The app registration is an enabled Application user in the environment, with a security role.' }
        [ordered]@{ id = 'contactcenter'; title = 'Contact Center';   description = 'Contact Center is installed: workstreams and queues can be read.' }
        [ordered]@{ id = 'access';        title = 'Table access';     description = 'Read, create, update and delete on every table the tool moves.' }
    )
}

function New-CcCheckResult([string] $status, [string] $summary, [string[]] $detail = @(), [string] $fix = $null) {
    [ordered]@{ status = $status; summary = $summary; detail = @($detail); fix = $fix; at = (Get-Date).ToUniversalTime().ToString('o') }
}

function Invoke-CcCheckRequest {
    # Never throws. Returns status 0 when the host could not be reached at all.
    param([string] $Method = 'Get', [string] $Uri, [hashtable] $Headers = @{}, $Body, [string] $ContentType)
    $params = @{ Method = $Method; Uri = $Uri; Headers = $Headers; SkipHttpErrorCheck = $true; TimeoutSec = 60; ErrorAction = 'Stop' }
    if ($null -ne $Body) { $params.Body = $Body }
    if ($ContentType) { $params.ContentType = $ContentType }
    try {
        $resp = Invoke-WebRequest @params
        $json = $null
        try { if ($resp.Content) { $json = $resp.Content | ConvertFrom-Json -Depth 40 } } catch { }
        return [pscustomobject]@{ Status = [int]$resp.StatusCode; Json = $json; Text = [string]$resp.Content; Error = $null }
    }
    catch {
        return [pscustomobject]@{ Status = 0; Json = $null; Text = $null; Error = $_.Exception.Message }
    }
}

function Get-CcDataverseError($resp) {
    if ($resp.Json -and $resp.Json.error -and $resp.Json.error.message) { return [string]$resp.Json.error.message }
    if ($resp.Error) { return $resp.Error }
    return "HTTP $($resp.Status)"
}

function ConvertFrom-CcJwt([string] $token) {
    $payload = $token.Split('.')[1].Replace('-', '+').Replace('_', '/')
    switch ($payload.Length % 4) { 2 { $payload += '==' } 3 { $payload += '=' } }
    return ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json)
}

function Get-CcEnvBase($entry) { $entry.url.TrimEnd('/') }

# --- Token, with the AADSTS codes a client's app registration actually produces ------------------

function Request-CcCheckToken($entry, [string] $secret) {
    $key = "$($entry.tenantId)|$($entry.clientId)|$($entry.url)|$([string]$secret.GetHashCode())"
    $cached = $script:CcCheckTokens[$key]
    if ($cached -and $cached.ExpiresOn -gt (Get-Date).AddMinutes(2)) { return $cached }

    $resp = Invoke-CcCheckRequest -Method Post -Uri "https://login.microsoftonline.com/$($entry.tenantId)/oauth2/v2.0/token" `
        -ContentType 'application/x-www-form-urlencoded' -Body @{
            grant_type = 'client_credentials'; client_id = $entry.clientId; client_secret = $secret
            scope = "$(Get-CcEnvBase $entry)/.default"
        }
    if ($resp.Status -eq 200 -and $resp.Json.access_token) {
        $tok = [pscustomobject]@{
            Ok = $true; AccessToken = $resp.Json.access_token; ExpiresOn = (Get-Date).AddSeconds([int]$resp.Json.expires_in)
            Code = $null; Description = $null; Status = 200
        }
        $script:CcCheckTokens[$key] = $tok
        return $tok
    }
    $code = $null; $desc = $resp.Error
    if ($resp.Json) {
        if ($resp.Json.error_codes) { $code = [int]@($resp.Json.error_codes)[0] }
        $desc = ([string]$resp.Json.error_description -split "`r?`n")[0]
    }
    return [pscustomobject]@{ Ok = $false; AccessToken = $null; Code = $code; Description = $desc; Status = $resp.Status }
}

function Get-CcTokenFix([int] $code, $entry, [string] $secret) {
    $looksLikeGuid = $secret -match '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'
    switch ($code) {
        7000215 {
            $s = 'The secret is wrong. Ask the client for the secret Value (shown once when the secret is created), not the Secret ID.'
            if ($looksLikeGuid) { $s = 'What you entered is a GUID, so it is almost certainly the Secret ID. ' + $s }
            return $s
        }
        7000222 { return 'The secret has expired. Ask the client to create a new client secret on this app registration and send you the Value.' }
        700016  { return "No app with client ID $($entry.clientId) exists in tenant $($entry.tenantId). Check both IDs against the app registration's Overview page - one of them is wrong, or the app lives in another tenant." }
        90002   { return 'The tenant was not found. Use the Directory (tenant) ID from the app registration Overview page.' }
        500011  { return "Entra knows the app but not this environment URL as a resource in this tenant. Check the environment URL, and that the environment belongs to the same tenant as the app registration." }
        7000112 { return 'The app registration is disabled in the tenant. Ask the client to enable it (Enterprise applications -> the app -> Properties -> Enabled for users to sign in).' }
        53003   { return 'Conditional Access blocked the sign-in. Ask the client to exclude this app registration (a workload identity) from the policy, or allow sign-ins from where you are.' }
        700027  { return 'The app expects a certificate, not a secret. Ask the client for a client secret on this app registration.' }
        default { return 'Send the error above to whoever manages the app registration on the client side.' }
    }
}

function Get-CcDataverseHeaders([string] $token) {
    @{ Authorization = "Bearer $token"; Accept = 'application/json'; 'OData-MaxVersion' = '4.0'; 'OData-Version' = '4.0' }
}

function Get-CcTokenOrFail($entry, [string] $secret) {
    $tok = Request-CcCheckToken $entry $secret
    if (-not $tok.Ok) {
        return @{ Fail = (New-CcCheckResult 'fail' 'Sign-in failed - run the Sign in check first.' @($tok.Description) (Get-CcTokenFix $tok.Code $entry $secret)) }
    }
    return @{ Token = $tok.AccessToken }
}

# --- 1. Tenant -----------------------------------------------------------------------------------

function Test-CcCheckTenant($entry, [string] $secret) {
    $resp = Invoke-CcCheckRequest -Uri "https://login.microsoftonline.com/$($entry.tenantId)/v2.0/.well-known/openid-configuration"
    if ($resp.Status -eq 0) {
        return New-CcCheckResult 'fail' 'Could not reach login.microsoftonline.com.' @($resp.Error) 'Check your network or proxy. Nothing is wrong with the app registration yet.'
    }
    if ($resp.Status -ne 200) {
        return New-CcCheckResult 'fail' 'Tenant not found.' @("Entra did not recognise '$($entry.tenantId)'.") 'Use the Directory (tenant) ID from the app registration Overview page. A verified domain such as contoso.onmicrosoft.com also works.'
    }
    $tid = ([string]$resp.Json.issuer -split '/')[3]
    $detail = @("Tenant ID: $tid")
    if ($tid -ne $entry.tenantId) { $detail += "You entered '$($entry.tenantId)', which resolves to that tenant." }
    return New-CcCheckResult 'pass' 'Tenant exists.' $detail
}

# --- 2. Sign in ----------------------------------------------------------------------------------

function Test-CcCheckSignin($entry, [string] $secret) {
    $tok = Request-CcCheckToken $entry $secret
    if (-not $tok.Ok) {
        $code = if ($tok.Code) { "AADSTS$($tok.Code)" } else { "HTTP $($tok.Status)" }
        return New-CcCheckResult 'fail' "Sign-in rejected ($code)." @($tok.Description) (Get-CcTokenFix $tok.Code $entry $secret)
    }
    $claims = ConvertFrom-CcJwt $tok.AccessToken
    $detail = @(
        "App: $($claims.app_displayname) ($($claims.appid))"
        "Token for: $($claims.aud)"
        "Valid until: $($tok.ExpiresOn.ToString('HH:mm'))"
    )
    return New-CcCheckResult 'pass' 'Signed in with the client ID and secret.' $detail
}

# --- 3. Application user -------------------------------------------------------------------------

function Test-CcCheckAppUser($entry, [string] $secret) {
    $t = Get-CcTokenOrFail $entry $secret; if ($t.Fail) { return $t.Fail }
    $h = Get-CcDataverseHeaders $t.Token
    $api = "$(Get-CcEnvBase $entry)/api/data/v9.2"

    $who = Invoke-CcCheckRequest -Uri "$api/WhoAmI" -Headers $h
    if ($who.Status -eq 0) {
        return New-CcCheckResult 'fail' 'Could not reach the environment.' @($who.Error) 'Check the environment URL. Copy it from the Power Platform admin center (Environment URL), e.g. https://contoso-dev.crm4.dynamics.com.'
    }
    if ($who.Status -in 401, 403) {
        $msg = Get-CcDataverseError $who
        if ($msg -match 'prv\w+') {
            return New-CcCheckResult 'fail' 'Application user exists but has no usable security role.' @($msg) 'Ask the client to give the Application user a security role in this environment (System Administrator, or a custom role covering the Contact Center tables).'
        }
        return New-CcCheckResult 'fail' 'The app registration is not an Application user in this environment.' @($msg) 'Ask the client to add it: Power Platform admin center -> this environment -> Settings -> Users + permissions -> Application users -> New app user -> pick this app registration and give it a security role.'
    }
    if ($who.Status -ne 200) {
        return New-CcCheckResult 'fail' "WhoAmI failed (HTTP $($who.Status))." @(Get-CcDataverseError $who) 'Check the environment URL and try again.'
    }
    $userId = $who.Json.UserId

    $user = Invoke-CcCheckRequest -Headers $h -Uri ("$api/systemusers($userId)?`$select=fullname,applicationid,isdisabled" +
        "&`$expand=systemuserroles_association(`$select=name)")
    $detail = @()
    $roles = @()
    if ($user.Status -eq 200) {
        $roles = @($user.Json.systemuserroles_association | ForEach-Object { $_.name })
        $detail += "User: $($user.Json.fullname)"
        $detail += "Roles: " + $(if ($roles) { $roles -join ', ' } else { 'none directly assigned' })
        if ($user.Json.isdisabled) {
            return New-CcCheckResult 'fail' 'The Application user is disabled.' $detail 'Ask the client to activate the Application user in the Power Platform admin center.'
        }
    }
    else {
        $detail += "Could not read the user record: $(Get-CcDataverseError $user)"
    }

    $ver = Invoke-CcCheckRequest -Uri "$api/RetrieveVersion()" -Headers $h
    if ($ver.Status -eq 200) { $detail += "Dataverse version: $($ver.Json.Version)" }

    if (-not $roles) {
        # Roles can come through a team instead; the access check is what really decides.
        return New-CcCheckResult 'warn' 'Application user found, but no role assigned directly.' $detail 'Fine if a team gives it a role. The Table access check confirms either way.'
    }
    return New-CcCheckResult 'pass' "Application user found ($($roles -join ', '))." $detail
}

# --- 4. Contact Center installed -----------------------------------------------------------------

function Test-CcCheckContactCenter($entry, [string] $secret) {
    $t = Get-CcTokenOrFail $entry $secret; if ($t.Fail) { return $t.Fail }
    $h = Get-CcDataverseHeaders $t.Token
    $h['Prefer'] = 'odata.maxpagesize=1'
    $api = "$(Get-CcEnvBase $entry)/api/data/v9.2"

    $def = Invoke-CcCheckRequest -Uri "$api/EntityDefinitions(LogicalName='msdyn_liveworkstream')?`$select=LogicalName" -Headers $h
    if ($def.Status -eq 404) {
        return New-CcCheckResult 'fail' 'Contact Center is not installed in this environment.' @('The workstream table (msdyn_liveworkstream) does not exist.') 'Check you picked the right environment. Contact Center (or Customer Service with unified routing) has to be installed before config can move in or out.'
    }

    $detail = @()
    foreach ($q in @(
            @{ label = 'Workstreams'; path = 'msdyn_liveworkstreams?$select=msdyn_liveworkstreamid&$count=true' }
            @{ label = 'Omnichannel queues'; path = 'queues?$select=queueid&$filter=msdyn_isomnichannelqueue eq true&$count=true' }
        )) {
        $r = Invoke-CcCheckRequest -Uri "$api/$($q.path)" -Headers $h
        if ($r.Status -ne 200) {
            return New-CcCheckResult 'fail' "Could not read $($q.label.ToLower())." @(Get-CcDataverseError $r) 'The Application user needs read access to Contact Center tables. Ask the client for a role that includes them, or System Administrator.'
        }
        $detail += "$($q.label): $($r.Json.'@odata.count')"
    }
    return New-CcCheckResult 'pass' 'Contact Center is installed.' $detail
}

# --- 5. Table access -----------------------------------------------------------------------------

function Test-CcCheckAccess($entry, [string] $secret) {
    $t = Get-CcTokenOrFail $entry $secret; if ($t.Fail) { return $t.Fail }
    $h = Get-CcDataverseHeaders $t.Token
    $api = "$(Get-CcEnvBase $entry)/api/data/v9.2"
    $manifest = Get-Content (Get-CcManifestPathForRunner) -Raw | ConvertFrom-Json

    $fails = [System.Collections.Generic.List[string]]::new()
    $warns = [System.Collections.Generic.List[string]]::new()
    $absent = [System.Collections.Generic.List[string]]::new()
    $writable = [System.Collections.Generic.List[object]]::new()
    $readable = 0

    # Where to read each table and which column to ask for. A version 2 manifest does not carry entity
    # set names or columns - the engine reads those from each environment - so ask this environment.
    $sets = @{}
    $meta = Invoke-CcCheckRequest -Uri "$api/EntityDefinitions?`$select=LogicalName,EntitySetName,PrimaryIdAttribute" -Headers $h
    if ($meta.Status -ne 200) {
        return New-CcCheckResult 'fail' 'Could not read the table list from this environment.' @(Get-CcDataverseError $meta) 'Table access could not be checked.'
    }
    foreach ($e in @($meta.Json.value)) { $sets[$e.LogicalName] = $e }

    # Read: one row from every table. A table this environment does not have (a channel that is not
    # installed) is a warning, not a blocker.
    $h['Prefer'] = 'odata.maxpagesize=1'
    foreach ($tbl in $manifest.tables) {
        $def = $sets[$tbl.logicalName]
        if (-not $def) { $absent.Add($tbl.logicalName); continue }
        $r = Invoke-CcCheckRequest -Uri "$api/$($def.EntitySetName)?`$select=$($def.PrimaryIdAttribute)" -Headers $h
        if ($r.Status -eq 200) {
            $readable++
            # Reference and detect tables are read to resolve lookups and to report; they are never
            # written, so no create, update or delete privilege is wanted for them.
            if ($tbl.move -notin 'detect', 'reference') { $writable.Add($tbl) }
        }
        elseif ($r.Status -eq 404 -or (Get-CcDataverseError $r) -match 'Resource not found|Could not find') { $absent.Add($tbl.logicalName) }
        elseif ($r.Status -eq 403) { $fails.Add("No read access: $($tbl.logicalName)") }
        else { $fails.Add("$($tbl.logicalName): $(Get-CcDataverseError $r)") }
    }

    # Write: the user's privileges, not a test write. Global depth matters - with User or Business
    # Unit depth the tool can only touch records it owns, and every update of existing config fails.
    $who = Invoke-CcCheckRequest -Uri "$api/WhoAmI" -Headers $h
    $privByName = @{}
    $judged = 0
    $privResp = Invoke-CcCheckRequest -Uri "$api/systemusers($($who.Json.UserId))/Microsoft.Dynamics.CRM.RetrieveUserPrivileges()" -Headers $h
    if ($privResp.Status -ne 200) {
        $warns.Add("Could not read the user's privileges ($(Get-CcDataverseError $privResp)). Create/update access was not checked.")
    }
    else {
        foreach ($p in @($privResp.Json.RolePrivileges)) {
            if ($p.PrivilegeName) { $privByName[$p.PrivilegeName.ToLowerInvariant()] = [string]$p.Depth }
        }

        # Only judge privileges that exist in this org; some child tables inherit from a parent.
        $wanted = @(foreach ($tbl in $writable) { foreach ($verb in 'Create', 'Write', 'Delete') { "prv$verb$($tbl.logicalName)" } })
        $existing = @{}
        for ($i = 0; $i -lt $wanted.Count; $i += 40) {
            $names = @($wanted | Select-Object -Skip $i -First 40)
            $list = ($names | ForEach-Object { "'$_'" }) -join ','
            $r = Invoke-CcCheckRequest -Headers (Get-CcDataverseHeaders $t.Token) -Uri ("$api/privileges?`$select=name&`$filter=Microsoft.Dynamics.CRM.In(PropertyName='name',PropertyValues=[$list])")
            foreach ($p in @($r.Json.value)) { $existing[$p.name.ToLowerInvariant()] = $true }
        }

        foreach ($tbl in $writable) {
            foreach ($verb in 'Create', 'Write', 'Delete') {
                $name = "prv$verb$($tbl.logicalName)".ToLowerInvariant()
                if (-not $existing.ContainsKey($name)) { continue }
                $judged++
                $depth = $privByName[$name]
                $verbText = @{ Create = 'create'; Write = 'update'; Delete = 'delete' }[$verb]
                if (-not $depth) {
                    if ($verb -eq 'Delete') { $warns.Add("No delete on $($tbl.logicalName) - rollback cannot remove records a run created.") }
                    else { $fails.Add("No $verbText on $($tbl.logicalName)") }
                }
                elseif ($depth -notin 'Global', '3') {
                    $warns.Add("$verbText on $($tbl.logicalName) is limited to $depth level - records owned by others cannot be changed.")
                }
            }
        }
    }

    $detail = @("Tables readable: $readable of $($manifest.tables.Count)")
    if ($privResp.Status -eq 200) { $detail += "Create, update and delete privileges checked: $judged" }
    if ($absent.Count) { $detail += "Not in this environment (skipped): $($absent -join ', ')" }
    $detail += $fails
    $detail += $warns

    if ($fails.Count) {
        return New-CcCheckResult 'fail' "$($fails.Count) access problem(s)." $detail 'Ask the client to give the Application user System Administrator in this environment, or a custom role with organization-level create, read, write and delete on the tables listed.'
    }
    if ($warns.Count) {
        return New-CcCheckResult 'warn' 'Readable, with some write limitations.' $detail 'The tool works, but the limits above will show up as warnings or failed records in a run. Organization-level privileges remove them.'
    }
    return New-CcCheckResult 'pass' 'Full access to every table the tool moves.' $detail
}

function Invoke-CcCheck([string] $checkId, $entry, [string] $secret) {
    switch ($checkId) {
        'tenant'        { return Test-CcCheckTenant $entry $secret }
        'signin'        { return Test-CcCheckSignin $entry $secret }
        'appuser'       { return Test-CcCheckAppUser $entry $secret }
        'contactcenter' { return Test-CcCheckContactCenter $entry $secret }
        'access'        { return Test-CcCheckAccess $entry $secret }
        default         { throw "Unknown check '$checkId'." }
    }
}
