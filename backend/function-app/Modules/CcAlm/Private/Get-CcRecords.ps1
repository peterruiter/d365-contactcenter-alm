function Get-CcRecords {
    <#
    .SYNOPSIS
        Reads every row of one manifest table from one environment, following @odata.nextLink.
        If a $select column does not exist on this org (a 400 "Could not find a property"), it retries
        the read without $select and reads all columns, so one stale column never fails the compare.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [pscustomobject] $Environment,
        [Parameter(Mandatory)] [pscustomobject] $Table
    )

    function Read-CcPages([string] $startPath) {
        $records = [System.Collections.Generic.List[object]]::new()
        $path = $startPath
        do {
            $page = Invoke-CcWebApi -Environment $Environment -Method Get -Path $path
            if ($page.value) { foreach ($r in $page.value) { $records.Add($r) } }
            $path = $page.'@odata.nextLink'
        } while ($path)
        return $records
    }

    $withSelect = $Table.entitySet
    if ($Table.select -and $Table.select.Count -gt 0) {
        $withSelect += '?$select=' + ($Table.select -join ',')
    }

    try {
        $records = Read-CcPages $withSelect
    }
    catch {
        if ($_.Exception.Message -match 'Could not find a property named') {
            Write-Warning "$($Table.logicalName): a `$select column does not exist on this org. Reading all columns instead. $($_.Exception.Message)"
            $records = Read-CcPages $Table.entitySet
        }
        elseif ($_.Exception.Message -match 'Resource not found for the segment|Could not find.*entity set|404') {
            Write-Warning "$($Table.logicalName): entity set '$($Table.entitySet)' not found on this org. Skipping this table. $($_.Exception.Message)"
            return [System.Collections.Generic.List[object]]::new()
        }
        else {
            throw
        }
    }

    Write-Verbose "$($Environment.Id): $($Table.logicalName) -> $($records.Count) rows"
    return $records
}
