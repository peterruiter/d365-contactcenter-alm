# Reads kept from a compare, so the plan check and the dry run after it do not read both
# environments again. Compare-CcConfig -ReadCache fills a cache and answers from it; the hosts
# store it next to the diff (a file for the local runner, a blob for the Function).
#
# Only reads are cached: table metadata and record pages, keyed by environment URL and request
# path. -FreshRecords makes the records of chosen environments come from Dataverse again (an apply
# re-reads the target it is about to write to) while their metadata still comes from the cache.

$script:CcReadCache = $null
$script:CcFreshUrls = @()

function Get-CcCacheUrl([pscustomobject] $Environment) { $Environment.Url.TrimEnd('/').ToLowerInvariant() }

function Invoke-CcCachedGet {
    param(
        [Parameter(Mandatory)] [pscustomobject] $Environment,
        [Parameter(Mandatory)] [string] $Path,
        [ValidateSet('schema', 'records')] [string] $Kind,
        [string] $Prefer = 'odata.include-annotations="*"'
    )
    $cache = $script:CcReadCache
    $url = Get-CcCacheUrl $Environment
    $key = "$url|$Path"
    $useCache = $cache -and -not ($Kind -eq 'records' -and $script:CcFreshUrls -contains $url)

    if ($useCache -and $cache.entries.ContainsKey($key)) {
        $hit = $cache.entries[$key]
        # A table that does not exist in the org was read as an error; replay the error.
        if ($hit -and $hit.PSObject.Properties.Name -contains '__ccalmError') { throw [string]$hit.__ccalmError }
        return $hit
    }
    try {
        $res = Invoke-CcWebApi -Environment $Environment -Method Get -Path $Path -Prefer $Prefer
    }
    catch {
        if ($cache -and $Kind -eq 'schema' -and $_.Exception.Message -match '404|does not exist|Could not find') {
            $cache.entries[$key] = [pscustomobject]@{ __ccalmError = $_.Exception.Message }
        }
        throw
    }
    if ($cache) { $cache.entries[$key] = $res }
    return $res
}
