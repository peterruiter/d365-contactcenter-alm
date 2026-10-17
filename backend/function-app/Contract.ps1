# Response mappers shared by the Azure Function (profile.ps1) and the local runner
# (scripts/run-local.ps1), so both return exactly the shapes the app expects (app/src/types/alm.ts).
# Labels come from the engine and the manifest; nothing here is hard-coded per table.

function ConvertTo-CcDiffContract($diff) {
    [ordered]@{
        diffId     = $diff.diffId
        source     = $diff.source
        target     = $diff.target
        generated  = $diff.generated
        summary    = $diff.summary
        tables     = @($diff.tables | ForEach-Object {
                [ordered]@{
                    table   = $_.table
                    label   = $_.label
                    group   = $_.group
                    stage   = [int]$_.stage
                    records = @($_.records | ForEach-Object {
                            $equal = $_.status -eq 'Equal'
                            [ordered]@{
                                matchKey    = $_.matchKey
                                status      = $_.status
                                displayName = $_.displayName
                                context     = $_.context
                                note        = $_.note
                                fields      = if ($equal) { @() } else { @($_.fields | ForEach-Object { [ordered]@{ name = $_.name; label = $_.label; kind = $_.kind; source = $_.source; target = $_.target } }) }
                                dependsOn   = if ($equal) { @() } else { @($_.dependsOn | ForEach-Object { [ordered]@{ table = $_.table; matchKey = $_.matchKey; label = $_.label; via = $_.via; deferred = [bool]$_.deferred } }) }
                            }
                        })
                }
            })
        detectOnly = @($diff.detectOnly | ForEach-Object { [ordered]@{ type = $_.type; table = $_.table; label = $_.label; record = $_.record; message = $_.message } })
        notices    = @($diff.notices | ForEach-Object { [ordered]@{ severity = $_.severity; table = $_.table; message = $_.message } })
    }
}

function ConvertTo-CcPlanContract($plan) {
    $manifest = $plan._context.Manifest
    $stageNumbers = @($plan.operations | ForEach-Object { [int]$_.stage }) | Select-Object -Unique | Sort-Object
    [ordered]@{
        planId     = $plan.planId
        diffId     = $plan.diffId
        source     = $plan.source
        target     = $plan.target
        created    = $plan.created
        summary    = $plan.summary
        operations = @($plan.operations | ForEach-Object {
                [ordered]@{
                    seq          = $_.seq
                    stage        = [int]$_.stage
                    table        = $_.table
                    tableLabel   = $_.tableLabel
                    op           = $_.op
                    matchKey     = $_.matchKey
                    displayName  = $_.displayName
                    context      = $_.context
                    status       = $_.status
                    autoIncluded = [bool]$_.autoIncluded
                    neededBy     = @($_.neededBy)
                    changes      = @($_.changes)
                    dependencies = @($_.dependencies | ForEach-Object { [ordered]@{ table = $_.table; matchKey = $_.matchKey; label = $_.label; via = $_.via; state = $_.state } })
                    blockers     = @($_.blockers | ForEach-Object {
                            [ordered]@{
                                code    = $_.code
                                message = $_.message
                                fix     = if ($_.fix) { [ordered]@{ action = $_.fix.action; table = $_.fix.table; matchKey = $_.fix.matchKey; label = $_.fix.label } } else { $null }
                            }
                        })
                    warnings     = @($_.warnings)
                }
            })
        ignored    = @($plan.ignored)
        stages     = @($stageNumbers | ForEach-Object {
                $n = [int]$_
                $s = @($manifest.stages) | Where-Object { [int]$_.stage -eq $n } | Select-Object -First 1
                [ordered]@{ stage = $n; label = if ($s) { $s.label } else { "Stage $n" }; description = if ($s) { $s.description } else { $null } }
            })
    }
}

function ConvertTo-CcRunContract($run, [string] $snapshotId) {
    $stages = foreach ($k in $run.stages.Keys) {
        $s = $run.stages[$k]
        [ordered]@{
            stage    = [int]($k -replace '\D')
            label    = $s.label
            state    = $s.state
            written  = $s.written
            warnings = @($s.warnings)
            items    = @($s.items | ForEach-Object {
                    [ordered]@{
                        seq = $_.seq; table = $_.table; tableLabel = $_.tableLabel; displayName = $_.displayName
                        context = $_.context; op = $_.op; outcome = $_.outcome; message = $_.message
                    }
                })
        }
    }
    [ordered]@{
        runId      = $run.runId
        mode       = if ($run.mode -eq 'Apply') { 'apply' } else { 'dryRun' }
        source     = $run.source
        target     = $run.target
        state      = $run.state
        snapshotId = $snapshotId
        startedAt  = $run.startedAt
        finishedAt = $run.finishedAt
        summary    = $run.summary
        stages     = @($stages | Sort-Object { $_.stage })
        problems   = @($run.problems)
    }
}

# --- Error text ---------------------------------------------------------------

function Get-CcErrorText($err) {
    # Full message plus where it threw, so a bare "null-valued expression" points at a line.
    $parts = @($err.Exception.Message)
    if ($err.InvocationInfo -and $err.InvocationInfo.PositionMessage) {
        $parts += $err.InvocationInfo.PositionMessage.Trim()
    }
    if ($err.ScriptStackTrace) {
        $parts += "Stack: " + ($err.ScriptStackTrace -replace "`r?`n", ' <- ')
    }
    return ($parts -join ' | ')
}
