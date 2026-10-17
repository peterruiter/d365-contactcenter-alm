# The JSON the Function and the local runner send the app (backend/function-app/Contract.ps1 and the
# stored run record), checked after a real ConvertTo-Json / parse round trip: every list the app
# reads must arrive as a list, however many items it has. PowerShell quietly turns a one-item array
# into a bare object and an empty one into null in some places; the app then fails on .length or
# .map and shows a white page.

BeforeAll {
    . (Join-Path $PSScriptRoot 'support/TestSupport.ps1')
    . (Join-Path $PSScriptRoot '../backend/function-app/Contract.ps1')

    function ConvertTo-CcWire($Object) {
        # What the app receives: the hosts serialise with ConvertTo-Json -Depth 40.
        $Object | ConvertTo-Json -Depth 40 | ConvertFrom-Json
    }

    function Assert-CcList($Value, [string] $What) {
        # ConvertFrom-Json gives object[] for every JSON array, empty or not; null or a bare object
        # means the JSON had no array there.
        if ($null -eq $Value -or $Value -isnot [array]) { throw "$What is not a list in the JSON (got $(if ($null -eq $Value) { 'null' } else { $Value.GetType().Name }))." }
    }

    $s = New-CcSyntheticScenario
    Mount-CcFakeDataverse -Orgs $s.Dev, $s.Test | Out-Null
    $diff = Compare-CcConfig -Environments $s.Envs -SourceId dev -TargetId test 6>$null
    $plan = New-CcPlan -Diff $diff 6>$null
}

Describe 'Compare response' {
    BeforeAll { $wire = ConvertTo-CcWire (ConvertTo-CcDiffContract $diff) }

    It 'sends every list as a list, also with zero or one item' {
        Assert-CcList $wire.tables 'tables'
        Assert-CcList $wire.detectOnly 'detectOnly'
        Assert-CcList $wire.notices 'notices'
        foreach ($t in $wire.tables) {
            Assert-CcList $t.records "$($t.table).records"
            foreach ($r in $t.records) {
                Assert-CcList $r.fields "$($t.table) '$($r.displayName)' fields"
                Assert-CcList $r.dependsOn "$($t.table) '$($r.displayName)' dependsOn"
            }
        }
    }

    It 'covers the cases that broke: same records, and changed ones with exactly one setting' {
        $rows = @($wire.tables | ForEach-Object { $_.records })
        @($rows | Where-Object status -eq 'Equal').Count | Should -BeGreaterThan 0
        @($rows | Where-Object { $_.status -eq 'Changed' -and $_.fields.Count -eq 1 }).Count | Should -BeGreaterThan 0
        @($rows | Where-Object { @($_.dependsOn).Count -eq 1 }).Count | Should -BeGreaterThan 0
    }

    It 'leaves out the settings of records that are the same' {
        $rows = @($wire.tables | ForEach-Object { $_.records } | Where-Object status -eq 'Equal')
        @($rows | Where-Object { $_.fields.Count -gt 0 }).Count | Should -Be 0
    }
}

Describe 'Plan response' {
    BeforeAll { $wire = ConvertTo-CcWire (ConvertTo-CcPlanContract $plan) }

    It 'sends every list as a list' {
        Assert-CcList $wire.operations 'operations'
        Assert-CcList $wire.ignored 'ignored'
        Assert-CcList $wire.stages 'stages'
        foreach ($o in $wire.operations) {
            foreach ($k in 'dependencies', 'blockers', 'warnings', 'neededBy', 'changes') { Assert-CcList $o.$k "$($o.displayName).$k" }
        }
    }

    It 'sends a plan for one record as a list of one' {
        $one = New-CcPlan -Diff $diff -Selection @(@{ table = 'msdyn_cannedmessage'; matchKey = (Get-CcDiffRow $diff msdyn_cannedmessage 'Greeting').matchKey }) 6>$null
        $w = ConvertTo-CcWire (ConvertTo-CcPlanContract $one)
        Assert-CcList $w.operations 'operations'
        Assert-CcList $w.stages 'stages'
        $w.operations.Count | Should -Be 1
    }
}

Describe 'Run record' {
    It 'sends items, stages, problems and the check afterwards as lists' {
        $s2 = New-CcSyntheticScenario
        $s2.Test.OnWrite = { param($method, $set, $record) if ($set -eq 'queues' -and $method -eq 'Post') { $record.msdyn_priority = 99 } }
        Mount-CcFakeDataverse -Orgs $s2.Dev, $s2.Test | Out-Null
        $p = New-CcPlan -Diff (Compare-CcConfig -Environments $s2.Envs -SourceId dev -TargetId test 6>$null) 6>$null
        $run = (Invoke-CcTestRun -Environments $s2.Envs -SourceId dev -TargetId test -Selection (Get-CcSelection $p)).Run
        $wire = ConvertTo-CcWire $run
        foreach ($k in 'items', 'stages', 'problems') { Assert-CcList $wire.$k $k }
        foreach ($st in $wire.stages) { Assert-CcList $st.items "stage $($st.stage) items"; Assert-CcList $st.warnings "stage $($st.stage) warnings" }
        Assert-CcList $wire.verification.differences 'verification.differences'
        Assert-CcList $wire.verification.added 'verification.added'
        foreach ($d in $wire.verification.differences) { Assert-CcList $d.fields "$($d.displayName) fields" }
    }

    It 'sends a run of one record as lists of one' {
        $s3 = New-CcSyntheticScenario
        Mount-CcFakeDataverse -Orgs $s3.Dev, $s3.Test | Out-Null
        $d3 = Compare-CcConfig -Environments $s3.Envs -SourceId dev -TargetId test 6>$null
        $sel = @(@{ table = 'msdyn_cannedmessage'; matchKey = (Get-CcDiffRow $d3 msdyn_cannedmessage 'Greeting').matchKey })
        $wire = ConvertTo-CcWire (Invoke-CcTestRun -Environments $s3.Envs -SourceId dev -TargetId test -Selection $sel).Run
        foreach ($k in 'items', 'stages', 'problems') { Assert-CcList $wire.$k $k }
        $wire.items.Count | Should -Be 1
        Assert-CcList $wire.verification.differences 'verification.differences'
    }
}
