function Connect-CcEnvironment {
    <#
    .SYNOPSIS
        Connects to the environments in a registry. Returns connected environment objects the other
        cmdlets consume.
    .DESCRIPTION
        Each environment can carry its own tenantId, clientId and clientSecret - a client hands out one
        app registration per environment, sometimes in different tenants. Anything an environment does
        not set falls back to the top-level registry value.

        Secret lookup per environment, first hit wins:
          1. clientSecret on the environment entry (the local runner passes it in memory, decrypted)
          2. CCALM_CLIENT_SECRET_<ID> environment variable (id upper-cased, non-alphanumerics as _)
          3. CCALM_CLIENT_SECRET environment variable
          4. clientSecret at the top of the registry
        Prefer environment variables. Never commit a secret.
    .PARAMETER ConfigPath
        Path to an environments.json built from config/environments.example.json.
    .PARAMETER Registry
        The registry as an object instead of a file. Used by the local runner, which keeps secrets out
        of plain-text files.
    .PARAMETER EnvironmentId
        Connect only these environments. A compare needs two; there is no reason to fail because a
        third is misconfigured.
    .PARAMETER SkipCheck
        Do not call WhoAmI on each environment before returning.
    .EXAMPLE
        $envs = Connect-CcEnvironment -ConfigPath ./environments.json
    .EXAMPLE
        $envs = Connect-CcEnvironment -ConfigPath ./environments.json -EnvironmentId dev, test
    #>
    [CmdletBinding(DefaultParameterSetName = 'File')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'File')] [string] $ConfigPath,
        [Parameter(Mandatory, ParameterSetName = 'Object')] [object] $Registry,
        [string[]] $EnvironmentId,
        [switch] $SkipCheck
    )

    if ($PSCmdlet.ParameterSetName -eq 'File') {
        if (-not (Test-Path $ConfigPath)) { throw "Environment registry not found at $ConfigPath" }
        $cfg = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
    }
    else {
        $cfg = $Registry
    }

    $apiVersion = 'v9.2'
    if ((Test-CcProp $cfg 'apiVersion') -and $cfg.apiVersion) { $apiVersion = $cfg.apiVersion }

    $entries = @($cfg.environments)
    if ($EnvironmentId) {
        $entries = @($entries | Where-Object { $EnvironmentId -contains $_.id })
        $missing = @($EnvironmentId | Where-Object { $entries.id -notcontains $_ })
        if ($missing) { throw "Environment(s) not in the registry: $($missing -join ', ')" }
    }

    $connected = foreach ($e in $entries) {
        $tenantId = Get-CcSetting $e $cfg 'tenantId'
        $clientId = Get-CcSetting $e $cfg 'clientId'
        if (-not $tenantId) { throw "No tenantId for $($e.name). Set it on the environment or at the top of the registry." }
        if (-not $clientId) { throw "No clientId for $($e.name). Set it on the environment or at the top of the registry." }

        $envVar = 'CCALM_CLIENT_SECRET_' + ($e.id.ToUpperInvariant() -replace '[^A-Z0-9]', '_')
        $secret = $null
        if ((Test-CcProp $e 'clientSecret') -and $e.clientSecret) { $secret = $e.clientSecret }
        elseif ([Environment]::GetEnvironmentVariable($envVar)) { $secret = [Environment]::GetEnvironmentVariable($envVar) }
        elseif ($env:CCALM_CLIENT_SECRET) { $secret = $env:CCALM_CLIENT_SECRET }
        elseif ((Test-CcProp $cfg 'clientSecret') -and $cfg.clientSecret) { $secret = $cfg.clientSecret }
        if (-not $secret -or $secret -like 'set-via-env-var*') {
            throw "No client secret for $($e.name). Set $envVar or CCALM_CLIENT_SECRET, or put it in the registry."
        }

        # role and requireApproval are optional per environment.
        $role = 'any'
        if ((Test-CcProp $e 'role') -and $e.role) { $role = $e.role }
        $requireApproval = $false
        if (Test-CcProp $e 'requireApproval') { $requireApproval = [bool]$e.requireApproval }

        # No closure. GetNewClosure() loses access to the module's private functions (Get-CcToken)
        # when the block runs later. Store what the token call needs; Invoke-CcWebApi calls
        # Get-CcToken directly, from module scope where it resolves.
        [pscustomobject]@{
            Id              = $e.id
            Name            = $e.name
            Url             = $e.url
            Role            = $role
            RequireApproval = $requireApproval
            ApiVersion      = $apiVersion
            TenantId        = $tenantId
            ClientId        = $clientId
            ClientSecret    = $secret
        }
    }

    # Fail fast: prove the token works for each environment.
    if (-not $SkipCheck) {
        foreach ($c in $connected) {
            try {
                $null = Invoke-CcWebApi -Environment $c -Method Get -Path 'WhoAmI'
                Write-Verbose "Connected to $($c.Name) ($($c.Url))"
            }
            catch {
                throw "Could not reach $($c.Name) ($($c.Url)). Check the app user and privileges. $($_.Exception.Message)"
            }
        }
    }

    return @($connected)
}
