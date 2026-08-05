function Get-CcRecords {
    <#
    .SYNOPSIS
        Reads every row of one manifest table from one environment, following @odata.nextLink.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [pscustomobject] $Environment,
        [Parameter(Mandatory)] [pscustomobject] $Table
    )

    $query = $Table.entitySet
    $parts = @()
    if ($Table.select -and $Table.select.Count -gt 0) {
        $parts += '$select=' + ($Table.select -join ',')
    }
    if ($parts.Count -gt 0) { $query += '?' + ($parts -join '&') }

    $records = [System.Collections.Generic.List[object]]::new()
    $path = $query

    do {
        $page = Invoke-CcWebApi -Environment $Environment -Method Get -Path $path
        if ($page.value) { foreach ($r in $page.value) { $records.Add($r) } }
        $path = $page.'@odata.nextLink'
    } while ($path)

    Write-Verbose "$($Environment.Id): $($Table.logicalName) -> $($records.Count) rows"
    return $records
}
