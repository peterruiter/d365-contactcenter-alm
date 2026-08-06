function Invoke-CcWebApi {
    <#
    .SYNOPSIS
        Calls the Dataverse Web API for one environment. Handles OData headers, service protection
        limits (429 + Retry-After), and exponential backoff.
    .PARAMETER Environment
        Connected environment object from Connect-CcEnvironment (holds Url, ApiVersion, and a token getter).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [pscustomobject] $Environment,
        [Parameter(Mandatory)] [ValidateSet('Get','Post','Patch','Delete','Put')] [string] $Method,
        [Parameter(Mandatory)] [string] $Path,
        [object] $Body,
        [hashtable] $ExtraHeaders,
        [string] $Prefer = 'odata.include-annotations="*"',
        [int] $MaxRetries = 6
    )

    $base = "$($Environment.Url.TrimEnd('/'))/api/data/$($Environment.ApiVersion)/"
    $uri  = if ($Path -match '^https?://') { $Path } else { $base + $Path.TrimStart('/') }

    $attempt = 0
    while ($true) {
        $attempt++
        $token = Get-CcToken -TenantId $Environment.TenantId -ClientId $Environment.ClientId `
            -ClientSecret $Environment.ClientSecret -ResourceUrl $Environment.Url
        $headers = @{
            'Authorization'    = "Bearer $token"
            'Accept'           = 'application/json'
            'OData-MaxVersion' = '4.0'
            'OData-Version'    = '4.0'
        }
        if ($Prefer) { $headers['Prefer'] = $Prefer }
        if ($ExtraHeaders) { foreach ($k in $ExtraHeaders.Keys) { $headers[$k] = $ExtraHeaders[$k] } }

        $params = @{
            Method      = $Method
            Uri         = $uri
            Headers     = $headers
            ContentType = 'application/json'
            ErrorAction = 'Stop'
        }
        if ($null -ne $Body) {
            $params.Body = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 40 -Compress }
        }

        try {
            return Invoke-RestMethod @params
        }
        catch {
            $resp = $_.Exception.Response
            $status = $null
            if ($resp) { $status = [int]$resp.StatusCode }

            # 204 No Content and successful upserts land here with no body in some hosts.
            if ($status -eq 204 -or $null -eq $status) {
                if ($null -eq $status) { throw }
                return $null
            }

            if ($status -eq 429 -and $attempt -le $MaxRetries) {
                $retryAfter = 0
                if ($resp.Headers -and $resp.Headers['Retry-After']) {
                    [int]::TryParse($resp.Headers['Retry-After'], [ref]$retryAfter) | Out-Null
                }
                if ($retryAfter -le 0) { $retryAfter = [math]::Min(60, [math]::Pow(2, $attempt)) }
                Write-Verbose "429 from $uri. Waiting $retryAfter s (attempt $attempt/$MaxRetries)."
                Start-Sleep -Seconds $retryAfter
                continue
            }

            if (($status -ge 500) -and $attempt -le $MaxRetries) {
                $wait = [math]::Min(30, [math]::Pow(2, $attempt))
                Write-Verbose "$status from $uri. Retrying in $wait s (attempt $attempt/$MaxRetries)."
                Start-Sleep -Seconds $wait
                continue
            }

            $detail = $_.ErrorDetails.Message
            throw "Web API $Method $uri failed with $status. $detail"
        }
    }
}
