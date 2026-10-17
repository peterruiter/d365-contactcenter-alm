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

function Complete-CcRun {
    # The final state of a run, from its items: Succeeded, PartiallyFailed or Failed.
    param($Run)
    $ok = 'created', 'updated', 'linked', 'unchanged', 'wouldCreate', 'wouldUpdate', 'wouldLink'
    $bad = @($Run.items | Where-Object { $_ -and $_.outcome -notin $ok })
    $good = @($Run.items | Where-Object { $_ -and $_.outcome -in $ok -and $_.outcome -ne 'unchanged' })
    $Run.state = if ($bad.Count -eq 0) { 'Succeeded' } elseif ($good.Count -eq 0) { 'Failed' } else { 'PartiallyFailed' }
    $Run.phase = 'done'
    $Run.progress.done = $Run.progress.total
    $Run.progress.current = $null
    $Run.finishedAt = (Get-Date).ToString('o')
}

function Invoke-CcRunVerification {
    # Compares again after an apply and stores what still differs on the run. A check that cannot
    # run (the target went away, a token expired) is reported on the run; it never fails the run,
    # whose writes stand either way.
    param($Run, [object[]] $Environments, [string] $ManifestPath, [scriptblock] $Save)
    $Run.phase = 'verifying'
    $Run.progress.current = 'Checking the target against the source'
    & $Save -Force
    try {
        $diff = Compare-CcConfig -Environments $Environments -SourceId $Run.source -TargetId $Run.target -ManifestPath $ManifestPath 6>$null
        $Run.verification = Get-CcVerification -Diff $diff -Items @($Run.items) -ExtraBefore $Run.extraBefore
    }
    catch {
        $Run.verification = [ordered]@{
            state = 'Error'; checkedAt = (Get-Date).ToString('o'); checked = 0; matched = 0; differences = @(); added = @()
            message = "The check afterwards could not run: $(Get-CcErrorMessage $_.Exception.Message)"
        }
    }
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
