function New-CcPlan {
    <#
    .SYNOPSIS
        Turns a diff into an ordered list of writes and checks, before anything runs, that every write
        can succeed: each record's parents, templates and embedded references must already be in the
        target, be created earlier in this run, or be linked in the final pass. Anything that cannot
        is blocked, with the reason and, where there is one, the fix.
    .PARAMETER Selection
        Records to move, as @{ table = 'queue'; matchKey = '...' }. Omit to plan every new and changed
        record.
    .PARAMETER IncludeDependencies
        Also plan the new records the selection needs. On by default; a dependency left out shows up
        as a blocker instead.
    .EXAMPLE
        $plan = New-CcPlan -Diff $diff
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [pscustomobject] $Diff,
        [object[]] $Selection,
        [bool] $IncludeDependencies = $true
    )

    $ctx = $Diff._context
    $manifest = $ctx.Manifest
    $maps = $ctx.Maps
    $plans = $ctx.TablePlans

    # Every diff record by "table|key".
    $byRef = @{}
    foreach ($td in $Diff.tables) {
        foreach ($r in $td.records) { $byRef["$($td.table)|$($r.matchKey)"] = [pscustomobject]@{ Table = $td.table; Record = $r } }
    }

    $movable = { param($ref) $e = $byRef[$ref]; $e -and $e.Record.status -in 'MissingInTarget', 'Changed' }
    $planned = [ordered]@{}        # ref -> reason it is in the plan
    $neededBy = @{}                # ref -> list of labels of records that pulled it in
    $ignored = [System.Collections.Generic.List[object]]::new()

    # No -Selection at all plans everything; an empty selection plans nothing. Testing it for
    # truth instead made an empty list - a run whose selection was lost - plan every record.
    $start = if ($null -ne $Selection) { @($Selection | Where-Object { $_ } | ForEach-Object { "$($_.table)|$($_.matchKey)" }) }
             else { @($byRef.Keys | Where-Object { & $movable $_ }) }
    foreach ($ref in $start) {
        if (& $movable $ref) { $planned[$ref] = 'selected' }
        elseif ($byRef[$ref]) {
            $r = $byRef[$ref].Record
            $why = switch ($r.status) {
                'Equal' { 'it is already the same in the target' }
                'ExtraInTarget' { 'it only exists in the target' }
                'Ambiguous' { $r.note }
                default { "its status is $($r.status)" }
            }
            $ignored.Add([pscustomobject]@{ table = $byRef[$ref].Table; matchKey = $byRef[$ref].Record.matchKey; displayName = $r.displayName; reason = "Not moved: $why" }) | Out-Null
        }
    }

    if ($IncludeDependencies) {
        $queue = [System.Collections.Generic.Queue[string]]::new()
        foreach ($ref in @($planned.Keys)) { $queue.Enqueue($ref) }
        while ($queue.Count -gt 0) {
            $ref = $queue.Dequeue()
            $entry = $byRef[$ref]
            foreach ($d in @($entry.Record.dependsOn | Where-Object { $_ })) {
                $dRef = "$($d.table)|$($d.matchKey)"
                $dEntry = $byRef[$dRef]
                if (-not $dEntry -or $dEntry.Record.status -ne 'MissingInTarget') { continue }
                if (-not $neededBy.ContainsKey($dRef)) { $neededBy[$dRef] = [System.Collections.Generic.List[string]]::new() }
                $who = Get-CcRefLabel $maps $entry.Table $entry.Record.matchKey $plans
                if (-not $neededBy[$dRef].Contains($who)) { $neededBy[$dRef].Add($who) | Out-Null }
                if (-not $planned.Contains($dRef)) {
                    $planned[$dRef] = 'dependency'
                    $queue.Enqueue($dRef)
                }
            }
        }
    }

    # Operations in write order.
    $ops = [System.Collections.Generic.List[object]]::new()
    $opByRef = @{}
    $orderOf = @{}; foreach ($t in $manifest.tables) { $orderOf[$t.logicalName] = [int]$t.order }
    $sorted = @($planned.Keys | Sort-Object { $orderOf[$byRef[$_].Table] }, { $byRef[$_].Record.displayName })
    $seq = 0
    foreach ($ref in $sorted) {
        $entry = $byRef[$ref]
        $t = $plans[$entry.Table].Table
        $r = $entry.Record
        $op = if ($r.status -eq 'MissingInTarget') { 'create' } else { 'update' }
        if ($t.move -eq 'create-once' -and $op -eq 'update') { $op = 'skip-existing' }
        $seq++
        $o = [pscustomobject]@{
            seq          = $seq
            stage        = [int]$t.stage
            order        = [int]$t.order
            table        = $entry.Table
            tableLabel   = Get-CcTableLabel $t
            op           = $op
            matchKey     = $r.matchKey
            displayName  = $r.displayName
            context      = $r.context
            autoIncluded = ($planned[$ref] -eq 'dependency')
            neededBy     = @(if ($neededBy[$ref]) { $neededBy[$ref] })
            changes      = @($r.fields | ForEach-Object { $_.label })
            status       = 'ready'
            dependencies = [System.Collections.Generic.List[object]]::new()
            blockers     = [System.Collections.Generic.List[object]]::new()
            warnings     = [System.Collections.Generic.List[string]]::new()
        }
        $ops.Add($o) | Out-Null
        $opByRef[$ref] = $o
    }

    # Preflight each operation.
    foreach ($o in $ops) {
        $tplan = $plans[$o.table]
        $r = $byRef["$($o.table)|$($o.matchKey)"].Record

        if ($o.op -eq 'skip-existing') {
            $o.warnings.Add('Already exists in the target. This table is only ever created, never changed, so it is left as it is.') | Out-Null
            continue
        }
        if ($o.op -eq 'create' -and $tplan.Table.move -eq 'update-only') {
            $o.blockers.Add([pscustomobject]@{ code = 'updateOnly'; message = "$($o.tableLabel) exist once per environment and are never created by this tool. Create it in the target first, then compare again."; fix = $null }) | Out-Null
        }
        if ($o.op -eq 'create') {
            foreach ($ext in $tplan.RequiredExternal) {
                $o.blockers.Add([pscustomobject]@{
                        code    = 'external'
                        message = "Needs a $($ext.Label.ToLowerInvariant()) to be created, and that is set up per environment. Set this channel up in the target, then compare again to copy its settings."
                        fix     = $null
                    }) | Out-Null
            }
        }

        foreach ($d in @($r.dependsOn | Where-Object { $_ })) {
            $dRef = "$($d.table)|$($d.matchKey)"
            $label = if ($d.matchKey -like 'unresolved:*') { "a $(Get-CcItemLabel $plans[$d.table].Table) that no longer exists in the source" } else { Get-CcRefLabel $maps $d.table $d.matchKey $plans }
            $dep = [pscustomobject]@{ table = $d.table; matchKey = $d.matchKey; label = $label; via = $d.via; state = $null }

            if ($maps.TargetKeyToGuid.ContainsKey($dRef)) {
                $dep.state = 'inTarget'
            }
            elseif ($opByRef.ContainsKey($dRef) -and $opByRef[$dRef].op -eq 'create') {
                $dep.state = if ($d.deferred) { 'linkedLater' } else { 'createdEarlier' }
            }
            elseif ($d.matchKey -like 'unresolved:*') {
                $dep.state = 'missing'
                $lk = $tplan.Lookups | Where-Object Label -eq $d.via | Select-Object -First 1
                if ($lk -and $lk.Required) {
                    $o.blockers.Add([pscustomobject]@{ code = 'danglingRequired'; message = "Its $($d.via) points at a record that no longer exists in the source. Fix it in the source first."; fix = $null }) | Out-Null
                }
                else {
                    $o.warnings.Add("Its $($d.via) points at a record that no longer exists in the source; that link is left empty.") | Out-Null
                }
            }
            else {
                $dep.state = 'missing'
                $dEntry = $byRef[$dRef]
                $srcRec = $null
                $srcId = Get-CcIdByKey -Env $ctx.Source -Table $d.table -Key $d.matchKey
                if ($srcId) { $srcRec = $ctx.Source.ById[$d.table][$srcId] }
                if ($dEntry -and $dEntry.Record.status -eq 'MissingInTarget') {
                    $o.blockers.Add([pscustomobject]@{
                            code    = 'missingDependency'
                            message = "Needs $label, which is not in the target and not selected."
                            fix     = [pscustomobject]@{ action = 'include'; table = $d.table; matchKey = $d.matchKey; label = "Add $label" }
                        }) | Out-Null
                }
                elseif ($srcRec -and $srcRec.ismanaged -eq $true) {
                    $o.blockers.Add([pscustomobject]@{ code = 'managedMissing'; message = "Needs $label, which comes with a managed solution that is not installed in the target. Install that solution there first."; fix = $null }) | Out-Null
                }
                elseif ($d.kind -eq 'name') {
                    $o.blockers.Add([pscustomobject]@{ code = 'notFound'; message = "Its $($d.via.ToLowerInvariant()) names $($d.matchKey -replace '^[^=]+=', "'")' which exists in neither environment. Fix it in the source first."; fix = $null }) | Out-Null
                }
                else {
                    $o.blockers.Add([pscustomobject]@{ code = 'notFound'; message = "Needs $label, which cannot be found in the target."; fix = $null }) | Out-Null
                }
            }
            $o.dependencies.Add($dep) | Out-Null
        }
        if ($o.blockers.Count -gt 0) { $o.status = 'blocked' }
    }

    # A record waiting on a blocked one is blocked too, until nothing changes.
    do {
        $changed = $false
        foreach ($o in $ops) {
            if ($o.status -eq 'blocked') { continue }
            foreach ($dep in $o.dependencies) {
                if ($dep.state -notin 'createdEarlier', 'linkedLater') { continue }
                $parent = $opByRef["$($dep.table)|$($dep.matchKey)"]
                if ($parent -and $parent.status -eq 'blocked') {
                    $o.blockers.Add([pscustomobject]@{ code = 'waitsOnBlocked'; message = "Waits on $($dep.label), which is blocked."; fix = $null }) | Out-Null
                    $o.status = 'blocked'
                    $changed = $true
                    break
                }
            }
        }
    } while ($changed)

    $plan = [pscustomobject]@{
        planId     = "pln_$([guid]::NewGuid().ToString('N').Substring(0, 12))"
        diffId     = $Diff.diffId
        source     = $Diff.source
        target     = $Diff.target
        created    = (Get-Date).ToString('o')
        operations = $ops
        ignored    = @($ignored)
        summary    = [pscustomobject]@{
            total        = $ops.Count
            ready        = @($ops | Where-Object status -eq 'ready').Count
            blocked      = @($ops | Where-Object status -eq 'blocked').Count
            autoIncluded = @($ops | Where-Object autoIncluded).Count
            creates      = @($ops | Where-Object op -eq 'create').Count
            updates      = @($ops | Where-Object op -eq 'update').Count
            links        = @($ops | ForEach-Object { $_.dependencies } | Where-Object state -eq 'linkedLater').Count
        }
        _context   = $ctx
    }

    $s = $plan.summary
    Write-Host "Plan $($plan.planId): $($s.total) records ($($s.creates) new, $($s.updates) changed), $($s.ready) ready, $($s.blocked) blocked$(if ($s.autoIncluded) { ", $($s.autoIncluded) added because they are needed" })." -ForegroundColor Cyan
    foreach ($o in @($ops | Where-Object status -eq 'blocked')) {
        Write-Host "  blocked: $($o.tableLabel) '$($o.displayName)': $(($o.blockers | ForEach-Object message) -join ' ')" -ForegroundColor Yellow
    }
    return $plan
}
