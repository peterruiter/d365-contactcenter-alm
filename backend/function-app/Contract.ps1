# Labels and response mappers shared by the Azure Function (profile.ps1) and the local runner
# (scripts/run-local.ps1), so both return exactly the shapes the app expects.

# --- Friendly labels for the UI ------------------------------------------------

function Get-CcTableLabels {
    @{
        msdyn_operatinghour                   = 'Operating hours'
        characteristic                        = 'Skills'
        ratingmodel                           = 'Rating models'
        ratingvalue                           = 'Rating values'
        msdyn_capacityprofile                 = 'Capacity profiles'
        msdyn_notificationtemplate            = 'Notification templates'
        msdyn_sessiontemplate                 = 'Session templates'
        msdyn_liveworkstream                  = 'Workstreams'
        msdyn_liveworkstreamcapacityprofile   = 'Workstream capacity'
        msdyn_ocliveworkstreamcontextvariable = 'Context variables'
        queue                                 = 'Queues'
        msdyn_decisioncontract                = 'Decision contracts'
        msdyn_decisionruleset                 = 'Routing rulesets'
        msdyn_routingconfiguration            = 'Routing config'
        msdyn_routingconfigurationstep        = 'Routing steps'
        msdyn_assignmentconfiguration         = 'Assignment config'
        msdyn_assignmentconfigurationstep     = 'Assignment steps'
        msdyn_livechatconfig                  = 'Live chat'
        msdyn_ocvoicechannelsetting           = 'Voice channel'
        msdyn_ocsmschannelsetting             = 'SMS channel'
        msdyn_ocwhatsappchannelnumber         = 'WhatsApp channel'
        msdyn_cannedmessage                   = 'Quick replies'
        msdyn_octag                           = 'Tags'
        msdyn_omnichannelconfiguration        = 'Omnichannel config'
    }
}

function Get-CcStageLabels {
    @{
        1  = 'Foundations (hours, skills, capacity, templates)'
        2  = 'Workstreams'
        3  = 'Workstream joins and context variables'
        4  = 'Queues'
        5  = 'Decision contracts'
        6  = 'Routing rulesets'
        7  = 'Routing and assignment steps'
        8  = 'Channel settings'
        9  = 'Quick replies and tags'
        10 = 'Omnichannel config'
    }
}

function Get-CcLabel([string] $logical) {
    # Self-contained: no reliance on $script: state, which does not resolve the same way when a
    # profile.ps1 function is invoked from a function's run.ps1 scope in Azure Functions.
    $map = Get-CcTableLabels
    if ($map.ContainsKey($logical)) { return $map[$logical] }
    return $logical
}

# --- Contract mappers: engine objects -> the shapes the app expects ------------

function ConvertTo-CcDiffContract($diff) {
    [ordered]@{
        source     = $diff.source
        target     = $diff.target
        generated  = $diff.generated
        summary    = $diff.summary
        tables     = @($diff.tables | ForEach-Object {
            [ordered]@{
                table   = $_.table
                label   = Get-CcLabel $_.table
                records = @($_.records | ForEach-Object {
                    [ordered]@{
                        matchKey    = $_.matchKey
                        status      = $_.status
                        fields      = @($_.fields)
                        dependsOn   = @($_.dependsOn | ForEach-Object { [ordered]@{ table = $_.table; matchKey = $_.matchKey } })
                        displayName = $_.displayName
                    }
                })
            }
        })
        detectOnly = @($diff.detectOnly)
    }
}

function ConvertTo-CcPlanContract($plan) {
    # Stage numbers get cast to [int] on every read and write below. Get-CcManifest parses JSON,
    # where ConvertFrom-Json hands back stage numbers as [Int64]; Get-CcStageLabels is a literal
    # PowerShell hashtable with [Int32] keys. A plain Hashtable hashes by the boxed value's runtime
    # type, so Int32(4) and Int64(4) are different keys - ContainsKey silently returns false across
    # the two, and every stage looked empty even though the plan had operations in it.
    $stageLabels = Get-CcStageLabels
    $opsByStage = @{}
    foreach ($op in $plan.operations) {
        $stageKey = [int]$op.stage
        if (-not $opsByStage.ContainsKey($stageKey)) { $opsByStage[$stageKey] = [System.Collections.Generic.List[object]]::new() }
        $opsByStage[$stageKey].Add($op) | Out-Null
    }
    # Every canonical stage shows up even with nothing to do in it, plus any stage the plan itself
    # used that isn't in the canonical list (belt and braces against manifest/label drift).
    $allStageNumbers = @($stageLabels.Keys | ForEach-Object { [int]$_ }) + @($opsByStage.Keys) | Select-Object -Unique | Sort-Object

    [ordered]@{
        planId     = $plan.planId
        source     = $plan.source
        target     = $plan.target
        created    = $plan.created
        operations = @($plan.operations | ForEach-Object {
            [ordered]@{
                seq = $_.seq; stage = $_.stage; table = $_.table
                label = Get-CcLabel $_.table; op = $_.op; matchKey = $_.matchKey
                displayName = $_.displayName
            }
        })
        stages = @($allStageNumbers | ForEach-Object {
            $stageNo = [int]$_
            $ops = if ($opsByStage.ContainsKey($stageNo)) { $opsByStage[$stageNo] } else { @() }
            [ordered]@{
                stage      = $stageNo
                label      = if ($stageLabels.ContainsKey($stageNo)) { $stageLabels[$stageNo] } else { "Stage $stageNo" }
                operations = @($ops | ForEach-Object {
                    [ordered]@{
                        seq = $_.seq; table = $_.table; label = Get-CcLabel $_.table
                        op = $_.op; matchKey = $_.matchKey; displayName = $_.displayName
                    }
                })
            }
        })
    }
}

function ConvertTo-CcRunContract($run, [string] $snapshotId) {
    $stageLabels = Get-CcStageLabels
    $stages = foreach ($k in $run.stages.Keys) {
        $stageNo = [int]($k -replace '\D')
        $s = $run.stages[$k]
        [ordered]@{
            stage    = $stageNo
            label    = if ($stageLabels.ContainsKey($stageNo)) { $stageLabels[$stageNo] } else { "Stage $stageNo" }
            state    = $s.state
            written  = $s.written
            warnings = @($s.warnings)
        }
    }
    [ordered]@{
        runId     = $run.runId
        mode      = if ($run.mode -eq 'Apply') { 'apply' } else { 'dryRun' }
        target    = $run.target
        state     = $run.state
        snapshotId = $snapshotId
        stages    = @($stages | Sort-Object stage)
        problems  = @($run.problems)
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
