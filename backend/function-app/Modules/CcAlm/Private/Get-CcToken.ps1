$script:CcTokenCache = @{}

function Get-CcToken {
    <#
    .SYNOPSIS
        Gets an access token for one environment via client credentials. Caches per resource until near expiry.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $TenantId,
        [Parameter(Mandatory)] [string] $ClientId,
        [Parameter(Mandatory)] [string] $ClientSecret,
        [Parameter(Mandatory)] [string] $ResourceUrl
    )

    $resource = $ResourceUrl.TrimEnd('/')
    $cacheKey = "$TenantId|$ClientId|$resource"

    $cached = $script:CcTokenCache[$cacheKey]
    if ($cached -and $cached.ExpiresOn -gt (Get-Date).AddMinutes(2)) {
        return $cached.AccessToken
    }

    $body = @{
        grant_type    = 'client_credentials'
        client_id     = $ClientId
        client_secret = $ClientSecret
        scope         = "$resource/.default"
    }

    $tokenUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"

    try {
        $resp = Invoke-RestMethod -Method Post -Uri $tokenUrl -Body $body -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop
    }
    catch {
        throw "Token request failed for $resource. $($_.Exception.Message)"
    }

    $script:CcTokenCache[$cacheKey] = [pscustomobject]@{
        AccessToken = $resp.access_token
        ExpiresOn   = (Get-Date).AddSeconds([int]$resp.expires_in)
    }

    return $resp.access_token
}
