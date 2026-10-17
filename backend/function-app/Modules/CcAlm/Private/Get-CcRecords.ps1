function Get-CcRecords {
    <#
    .SYNOPSIS
        Reads every row of one table from one environment, following @odata.nextLink. The columns
        come from the table plan, which only lists columns both orgs have, so a $select never names
        a column the org does not know.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [pscustomobject] $Environment,
        [Parameter(Mandatory)] [string] $EntitySet,
        [Parameter(Mandatory)] [string[]] $Select
    )

    $records = [System.Collections.Generic.List[object]]::new()
    $path = "$EntitySet`?`$select=$($Select -join ',')"
    do {
        $page = Invoke-CcCachedGet -Environment $Environment -Path $path -Kind records
        if ($page.value) { foreach ($r in $page.value) { $records.Add($r) } }
        $path = $page.'@odata.nextLink'
    } while ($path)

    Write-Verbose "$($Environment.Id): $EntitySet -> $($records.Count) rows"
    return $records
}
