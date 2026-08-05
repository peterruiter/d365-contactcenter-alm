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
    if (-not $secret) { $secret = $cfg.clientSecret }
    if (-not $secret -or $secret -like 'set-via-env-var*') {
        throw "No client secret. Set CCALM_CLIENT_SECRET or put it in the registry file."
    }

    $apiVersion = if ($cfg.apiVersion) { $cfg.apiVersion } else { 'v9.2' }

    $connected = foreach ($e in $cfg.environments) {
        $url = $e.url
        $tenantId = $cfg.tenantId
        $clientId = $cfg.clientId

        # Closure so each env gets a fresh, cached token on demand.
        $getter = {
            Get-CcToken -TenantId $tenantId -ClientId $clientId -ClientSecret $secret -ResourceUrl $url
        }.GetNewClosure()

        [pscustomobject]@{
            Id              = $e.id
            Name            = $e.name
            Url             = $url
            Role            = $e.role
            RequireApproval = [bool]$e.requireApproval
            ApiVersion      = $apiVersion
            TokenGetter     = $getter
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
