# Shared by the background run cmdlets.

function Update-CcRunTotals {
    # Recomputes summary, stages and problems from the item list, so the stored run always reads
    # the same way however many slices it took.
    param($Run, $Manifest)
    $ok = 'created', 'updated', 'linked', 'unchanged', 'wouldCreate', 'wouldUpdate', 'wouldLink'
    $items = @($Run.items | Where-Object { $_ })
    $Run.summary = [ordered]@{
        created = @($items | Where-Object { $_.outcome -in 'created', 'wouldCreate' }).Count
        updated = @($items | Where-Object { $_.outcome -in 'updated', 'wouldUpdate' }).Count
        linked  = @($items | Where-Object { $_.outcome -in 'linked', 'wouldLink' }).Count
        skipped = @($items | Where-Object { $_.outcome -eq 'skipped' }).Count
        blocked = @($items | Where-Object { $_.outcome -eq 'blocked' }).Count
        failed  = @($items | Where-Object { $_.outcome -eq 'failed' }).Count
    }
    $Run.stages = @($items | Group-Object { [int]$_.stage } | Sort-Object { [int]$_.Name } | ForEach-Object {
            $si = @($_.Group)
            $bad = @($si | Where-Object { $_.outcome -notin $ok })
            $good = @($si | Where-Object { $_.outcome -in $ok -and $_.outcome -ne 'unchanged' })
            [ordered]@{
                stage    = [int]$_.Name
                label    = Get-CcStageLabel $Manifest ([int]$_.Name)
                state    = if ($bad.Count -eq 0) { 'Succeeded' } elseif ($good.Count -eq 0) { 'Failed' } else { 'PartiallyFailed' }
                written  = $good.Count
                warnings = @($bad | ForEach-Object { "$($_.tableLabel) '$($_.displayName)': $($_.message)" })
                items    = $si
            }
        })
    $Run.problems = @($items | Where-Object { $_.outcome -notin $ok } | ForEach-Object { "$($_.tableLabel) '$($_.displayName)': $($_.message)" })
}

function ConvertTo-CcHashtable {
    # A run read back from JSON is a PSCustomObject; turn it (and its nested objects) into ordered
    # hashtables so properties can be added and set the same way as on a new run.
    param($InputObject)
    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [System.Collections.IDictionary]) { return $InputObject }
    if ($InputObject -is [pscustomobject]) {
        $h = [ordered]@{}
        foreach ($p in $InputObject.PSObject.Properties) {
            $v = $p.Value
            $h[$p.Name] = if ($v -is [pscustomobject] -and $p.Name -in 'progress', 'summary', 'request', 'cleanup') { ConvertTo-CcHashtable $v } else { $v }
        }
        return $h
    }
    return $InputObject
}
