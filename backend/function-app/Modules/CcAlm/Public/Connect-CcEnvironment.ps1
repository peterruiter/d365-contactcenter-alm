function Connect-CcEnvironment {
    <#
    .SYNOPSIS
        Connects to the environments in a registry file using one service principal. Returns connected
        environment objects the other cmdlets consume.
    .DESCRIPTION
        The client secret is read from the CCALM_CLIENT_SECRET environment variable if present, otherwise
        from the registry file. Prefer the environment variable. Never commit a secret.
    .PARAMETER ConfigPath
        Path to an environments.json built from config/environments.example.json.
    .EXAMPLE
        $envs = Connect-CcEnvironment -ConfigPath ./environments.json
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $ConfigPath
    )

    if (-not (Test-Path $ConfigPath)) { throw "Environment registry not found at $ConfigPath" }
    $cfg = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json

    $secret = $env:CCALM_CLIENT_SECRET
    if (-not $secret -and ($cfg.PSObject.Properties.Name -contains 'clientSecret')) { $secret = $cfg.clientSecret }
    if (-not $secret -or $secret -like 'set-via-env-var*') {
        throw "No client secret. Set CCALM_CLIENT_SECRET or put it in the registry file."
    }

    $apiVersion = 'v9.2'
    if (($cfg.PSObject.Properties.Name -contains 'apiVersion') -and $cfg.apiVersion) { $apiVersion = $cfg.apiVersion }

    $connected = foreach ($e in $cfg.environments) {
        $url = $e.url
        $tenantId = $cfg.tenantId
        $clientId = $cfg.clientId

        # role and requireApproval are optional per environment.
        $role = 'any'
        if ($e.PSObject.Properties.Name -contains 'role' -and $e.role) { $role = $e.role }
        $requireApproval = $false
        if ($e.PSObject.Properties.Name -contains 'requireApproval') { $requireApproval = [bool]$e.requireApproval }

        # No closure. GetNewClosure() loses access to the module's private functions (Get-CcToken)
        # when the block runs later. Store what the token call needs; Invoke-CcWebApi calls
        # Get-CcToken directly, from module scope where it resolves.
        [pscustomobject]@{
            Id              = $e.id
            Name            = $e.name
            Url             = $url
            Role            = $role
            RequireApproval = $requireApproval
            ApiVersion      = $apiVersion
            TenantId        = $tenantId
            ClientId        = $clientId
            ClientSecret    = $secret
        }
    }

    # Fail fast: prove the token works for each environment.
    foreach ($c in $connected) {
        try {
            $null = Invoke-CcWebApi -Environment $c -Method Get -Path 'WhoAmI'
            Write-Verbose "Connected to $($c.Name) ($($c.Url))"
        }
        catch {
            throw "Could not reach $($c.Name) ($($c.Url)). Check the app user and privileges. $($_.Exception.Message)"
        }
    }

    return @($connected)
}
