# The whole engine on the synthetic Dev and Test (tests/support/SyntheticScenario.ps1): compare,
# plan, dry run, apply, the check afterwards, rollback, and runs split over time-budgeted slices.

BeforeAll {
    . (Join-Path $PSScriptRoot 'support/TestSupport.ps1')
}

Describe 'Compare' {
    BeforeAll {
        $s = New-CcSyntheticScenario
        Mount-CcFakeDataverse -Orgs $s.Dev, $s.Test | Out-Null
        $diff = Compare-CcConfig -Environments $s.Envs -SourceId dev -TargetId test 6>$null
        $rows = Get-CcAllRows $diff
    }

    It 'pairs records by what they are, not by GUID' {
        (Get-CcDiffRow $diff msdyn_operatinghour 'Office hours').status | Should -Be 'Equal'
        (Get-CcDiffRow $diff queue 'Billing queue').status | Should -Be 'Equal'
        (Get-CcDiffRow $diff msdyn_sessiontemplate 'Chat session').status | Should -Be 'Equal'
    }

    It 'sees a ruleset as unchanged when its definition points at the same records under other GUIDs' {
        (Get-CcDiffRow $diff msdyn_decisionruleset 'Billing route').status | Should -Be 'Equal'
    }

    It 'lists exactly the setting that changed, by its label' {
        $r = Get-CcDiffRow $diff msdyn_liveworkstream 'Billing chat'
        $r.status | Should -Be 'Changed'
        @($r.fields).Count | Should -Be 1
        $r.fields[0].label | Should -Be 'Capacity'
        $r.fields[0].source | Should -Be '2'
        $r.fields[0].target | Should -Be '1'
    }

    It 'tells duplicate names apart with the tie-breaker on both sides' {
        $cap = @(Get-CcDiffRow $diff msdyn_capacityprofile 'Chat capacity')
        @($cap.status | Sort-Object) | Should -Be @('Equal', 'MissingInTarget')
    }

    It 'never pairs records it cannot tell apart' {
        $vip = Get-CcDiffRow $diff msdyn_octag 'VIP'
        $vip.status | Should -Be 'Ambiguous'
        $vip.note | Should -Match '2 records in the source'
    }

    It 'reports what only the target has, and leaves personal queues out' {
        (Get-CcDiffRow $diff msdyn_octag 'Old tag').status | Should -Be 'ExtraInTarget'
        @(Get-CcDiffRow $diff queue '<Peter>').Count | Should -Be 0
    }

    It 'finds a changed step under an unchanged routing configuration' {
        (Get-CcDiffRow $diff msdyn_routingconfiguration 'Contact center routing configuration' 'Billing chat').status | Should -Be 'Equal'
        $step = Get-CcDiffRow $diff msdyn_routingconfigurationstep 'Route to queue' 'Billing chat › Contact center routing configuration'
        $step.status | Should -Be 'Changed'
        $step.fields.label | Should -Be @('Rule set')
    }

    It 'gives every dependency a real record (no phantom "needs a ,")' {
        $deps = @($rows | ForEach-Object { $_.dependsOn })
        $deps.Count | Should -BeGreaterThan 0
        @($deps | Where-Object { -not $_ -or -not $_.table -or -not $_.matchKey -or -not $_.label }).Count | Should -Be 0
        @((Get-CcDiffRow $diff msdyn_cannedmessage 'Greeting').dependsOn).Count | Should -Be 0
    }

    It 'flags what has to be set up per environment' {
        @($diff.detectOnly | ForEach-Object { "$($_.type):$($_.record)" }) | Should -Be @('channelAccount:Mortgage WhatsApp')
    }

    It 'finds nothing to move between an environment and itself' {
        $self = @((New-CcFakeEnvironment a A $s.Dev), (New-CcFakeEnvironment b B $s.Dev))
        $d = Compare-CcConfig -Environments $self -SourceId a -TargetId b 6>$null
        $d.summary.missingInTarget | Should -Be 0
        $d.summary.changed | Should -Be 0
        $d.summary.extraInTarget | Should -Be 0
    }
}

Describe 'Plan' {
    BeforeAll {
        $s = New-CcSyntheticScenario
        Mount-CcFakeDataverse -Orgs $s.Dev, $s.Test | Out-Null
        $diff = Compare-CcConfig -Environments $s.Envs -SourceId dev -TargetId test 6>$null
        $plan = New-CcPlan -Diff $diff 6>$null
        $op = { param($table, $name) $plan.operations | Where-Object { $_.table -eq $table -and $_.displayName -eq $name } | Select-Object -First 1 }
    }

    It 'blocks only what cannot be written, each with its reason' {
        @($plan.operations | Where-Object status -eq 'blocked' | ForEach-Object displayName | Sort-Object) | Should -Be @('GPT chat', 'Mortgage WhatsApp')
        (& $op msdyn_liveworkstream 'GPT chat').blockers.code | Should -Be @('managedMissing')
        (& $op msdyn_ocwhatsappchannelnumber 'Mortgage WhatsApp').blockers.code | Should -Contain 'external'
    }

    It 'plans records without dependencies as ready' {
        (& $op msdyn_cannedmessage 'Greeting').status | Should -Be 'ready'
        @((& $op msdyn_cannedmessage 'Greeting').dependencies).Count | Should -Be 0
        (& $op msdyn_octag 'Escalated').status | Should -Be 'ready'
    }

    It 'never changes a decision contract that already exists' {
        (& $op msdyn_decisioncontract 'Billing contract').op | Should -Be 'skip-existing'
    }

    It 'links a lookup to a table written later at the end' {
        $dq = (& $op msdyn_liveworkstream 'Mortgage chat').dependencies | Where-Object { $_.label -eq "queue 'Mortgage queue'" }
        $dq.state | Should -Be 'linkedLater'
    }

    It 'adds everything a selected record needs' {
        $diffStep = Get-CcDiffRow $diff msdyn_routingconfigurationstep 'Route to queue' 'Mortgage chat › Contact center routing configuration'
        $p = New-CcPlan -Diff $diff -Selection @(@{ table = 'msdyn_routingconfigurationstep'; matchKey = $diffStep.matchKey }) 6>$null
        $names = @($p.operations | ForEach-Object displayName)
        foreach ($n in 'Route to queue', 'Contact center routing configuration', 'Mortgage chat', 'Mortgage route', 'Mortgage queue', 'Mortgage contract', 'Mortgages', 'Mortgage session', 'Mortgage notification') {
            $names | Should -Contain $n
        }
        $p.summary.blocked | Should -Be 0
        @($p.operations | Where-Object autoIncluded).Count | Should -Be ($p.operations.Count - 1)
    }

    It 'offers the fix when a needed record is left out' {
        $diffStep = Get-CcDiffRow $diff msdyn_routingconfigurationstep 'Route to queue' 'Mortgage chat › Contact center routing configuration'
        $p = New-CcPlan -Diff $diff -Selection @(@{ table = 'msdyn_routingconfigurationstep'; matchKey = $diffStep.matchKey }) -IncludeDependencies $false 6>$null
        $b = $p.operations[0].blockers | Where-Object code -eq 'missingDependency'
        @($b).Count | Should -BeGreaterThan 0
        @($b | Where-Object { $_.fix.action -eq 'include' }).Count | Should -Be @($b).Count
    }
}

Describe 'Dry run' {
    BeforeAll {
        $s = New-CcSyntheticScenario
        Mount-CcFakeDataverse -Orgs $s.Dev, $s.Test | Out-Null
        $diff = Compare-CcConfig -Environments $s.Envs -SourceId dev -TargetId test 6>$null
        $plan = New-CcPlan -Diff $diff 6>$null
        $result = Invoke-CcTestRun -Environments $s.Envs -SourceId dev -TargetId test -Mode dryRun -Selection (Get-CcSelection $plan)
    }

    It 'writes nothing' {
        $s.Test.Writes.Count | Should -Be 0
    }

    It 'goes through every write and fails none' {
        $run = $result.Run
        $run.summary.failed | Should -Be 0
        $run.summary.skipped | Should -Be 0
        $run.summary.created | Should -Be @($plan.operations | Where-Object { $_.status -eq 'ready' -and $_.op -eq 'create' }).Count
        $run.summary.linked | Should -Be 3
        $run.verification | Should -BeNullOrEmpty
    }
}

Describe 'Apply, check afterwards and roll back' {
    BeforeAll {
        $s = New-CcSyntheticScenario
        $before = Copy-CcFakeOrg $s.Test -Url 'https://contoso-test-before.crm4.dynamics.com'
        Mount-CcFakeDataverse -Orgs $s.Dev, $s.Test, $before | Out-Null
        $diff = Compare-CcConfig -Environments $s.Envs -SourceId dev -TargetId test 6>$null
        $plan = New-CcPlan -Diff $diff 6>$null
        $result = Invoke-CcTestRun -Environments $s.Envs -SourceId dev -TargetId test -Mode apply -Selection (Get-CcSelection $plan)
        $run = $result.Run
        $after = Compare-CcConfig -Environments $s.Envs -SourceId dev -TargetId test 6>$null
    }

    It 'writes every ready record and fails none' {
        $run.summary.failed | Should -Be 0
        $run.summary.skipped | Should -Be 0
        $run.summary.blocked | Should -Be 2
        $run.state | Should -Be 'PartiallyFailed'
    }

    It 'checks every record it wrote and finds each the same as the source' {
        $v = $run.verification
        $v.state | Should -Be 'Verified'
        $v.checked | Should -Be ($run.summary.created + $run.summary.updated)
        $v.matched | Should -Be $v.checked
        @($v.differences).Count | Should -Be 0
        @($v.added).Count | Should -Be 0
    }

    It 'leaves only the blocked records to move' {
        $plan2 = New-CcPlan -Diff $after 6>$null
        @($plan2.operations | Where-Object op -ne 'skip-existing' | ForEach-Object displayName | Sort-Object) | Should -Be @('GPT chat', 'Mortgage WhatsApp')
    }

    It "rewrites a ruleset's embedded GUIDs to the target's records" {
        $route = $s.Test.Tables['msdyn_decisionruleset'].Rows | Where-Object msdyn_uniquename -eq 'contoso_mortgage_route'
        $queue = $s.Test.Tables['queue'].Rows | Where-Object name -eq 'Mortgage queue'
        $route.msdyn_rulesetdefinition | Should -Match $queue.queueid
        $route.msdyn_rulesetdefinition | Should -Not -Match $s.Ids.dev.mortgageQueue
    }

    It 'sets the links to later tables in the final pass' {
        $ws = $s.Test.Tables['msdyn_liveworkstream'].Rows | Where-Object msdyn_name -eq 'Mortgage chat'
        $queue = $s.Test.Tables['queue'].Rows | Where-Object name -eq 'Mortgage queue'
        $ws._msdyn_defaultqueue_value | Should -Be $queue.queueid
    }

    It 'writes each ruleset with an update body the second time' {
        $second = @($s.Test.Writes | Where-Object { $_.Set -eq 'msdyn_decisionrulesets' -and $_.Method -eq 'Patch' })
        $second.Count | Should -Be 1
        $second[0].Body.Contains('msdyn_uniquename') | Should -BeFalse
    }

    It 'puts the target back exactly as it was when rolled back' {
        $store = @{ Run = $run }
        Invoke-CcRollbackJob -Environments $s.Envs -SnapshotPath $result.SnapshotPath -LoadRun { $store.Run | ConvertTo-Json -Depth 40 | ConvertFrom-Json } -SaveRun { param($r) $store.Run = $r }
        $store.Run.state | Should -Be 'RolledBack'
        $store.Run.cleanup.deleted | Should -Be $run.summary.created
        @($store.Run.cleanup.unresolved).Count | Should -Be 0

        $envs = @((New-CcFakeEnvironment before Before $before), (New-CcFakeEnvironment test Test $s.Test))
        $d = Compare-CcConfig -Environments $envs -SourceId before -TargetId test 6>$null
        $d.summary.missingInTarget | Should -Be 0
        $d.summary.extraInTarget | Should -Be 0
        $d.summary.changed | Should -Be 0
    }
}

Describe 'Runs split over time-budgeted slices' {
    BeforeAll {
        $s = New-CcSyntheticScenario
        # Every Web API call takes a virtual second: a compare is about a minute (two after a schema
        # reload), so a two-minute slice ends mid-run and the check gets a slice of its own.
        Mount-CcFakeDataverse -Orgs $s.Dev, $s.Test -LatencySeconds 1 | Out-Null
        $diff = Compare-CcConfig -Environments $s.Envs -SourceId dev -TargetId test 6>$null
        $plan = New-CcPlan -Diff $diff 6>$null
        $result = Invoke-CcTestRun -Environments $s.Envs -SourceId dev -TargetId test -Mode apply -Selection (Get-CcSelection $plan) -TimeBudgetSeconds 120
        $run = $result.Run
    }

    It 'takes more than one slice and finishes' {
        $result.Slices | Should -BeGreaterThan 1
        $result.Finished | Should -BeTrue
        $run.phase | Should -Be 'done'
        $run.executions | Should -Be $result.Slices
    }

    It 'ends where a single run ends: everything written once, all of it checked' {
        $run.summary.failed | Should -Be 0
        $run.summary.blocked | Should -Be 2
        $run.verification.state | Should -Be 'Verified'
        $d = Compare-CcConfig -Environments $s.Envs -SourceId dev -TargetId test 6>$null
        $d.summary.ambiguous | Should -Be 1   # only VIP, which was ambiguous in Dev to begin with
        @($s.Test.Tables['msdyn_liveworkstream'].Rows | Where-Object msdyn_name -eq 'Mortgage chat').Count | Should -Be 1
        @($s.Test.Tables['queue'].Rows | Where-Object name -eq 'Mortgage queue').Count | Should -Be 1
    }

    It 'keeps one item per record across slices' {
        $keys = @($run.items | Where-Object op -ne 'link' | ForEach-Object { "$($_.table)|$($_.matchKey)" })
        $keys.Count | Should -Be @($keys | Select-Object -Unique).Count
    }
}

Describe 'What the check afterwards reports' {
    It 'records Dataverse added on its own during the run' {
        $s = New-CcSyntheticScenario -ProvisionRoutingConfiguration
        Mount-CcFakeDataverse -Orgs $s.Dev, $s.Test | Out-Null
        $plan = New-CcPlan -Diff (Compare-CcConfig -Environments $s.Envs -SourceId dev -TargetId test 6>$null) 6>$null
        $v = (Invoke-CcTestRun -Environments $s.Envs -SourceId dev -TargetId test -Selection (Get-CcSelection $plan)).Run.verification
        $added = @($v.added | ForEach-Object { "$($_.table):$($_.displayName)" })
        @($added | Where-Object { $_ -like 'msdyn_routingconfiguration:RC - Workstream: Mortgage chat (*' }).Count | Should -Be 1
        @($added | Where-Object { $_ -like 'msdyn_routingconfigurationstep:RCS - Workstream: Mortgage chat (*' }).Count | Should -Be 1
        @($added | Where-Object { $_ -like '*Old tag*' }).Count | Should -Be 0
    }

    It 'a write that Dataverse changed afterwards, with both values' {
        $s = New-CcSyntheticScenario
        $s.Test.OnWrite = { param($method, $set, $record) if ($set -eq 'queues' -and $method -eq 'Post') { $record.msdyn_priority = 99 } }
        Mount-CcFakeDataverse -Orgs $s.Dev, $s.Test | Out-Null
        $plan = New-CcPlan -Diff (Compare-CcConfig -Environments $s.Envs -SourceId dev -TargetId test 6>$null) 6>$null
        $v = (Invoke-CcTestRun -Environments $s.Envs -SourceId dev -TargetId test -Selection (Get-CcSelection $plan)).Run.verification
        $v.state | Should -Be 'Differences'
        $v.matched | Should -Be ($v.checked - 1)
        $d = $v.differences[0]
        $d.displayName | Should -Be 'Mortgage queue'
        $d.status | Should -Be 'Changed'
        $d.fields[0].label | Should -Be 'Priority'
        "$($d.fields[0].source)|$($d.fields[0].target)" | Should -Be '2|99'
    }

    It 'a failed write with what Dataverse said, holding back only what depends on it' {
        $s = New-CcSyntheticScenario
        $s.Test.FailWhen = { param($method, $set, $body) if ($set -eq 'queues' -and $method -eq 'Post') { 'A queue with this name already exists.' } }
        Mount-CcFakeDataverse -Orgs $s.Dev, $s.Test | Out-Null
        $plan = New-CcPlan -Diff (Compare-CcConfig -Environments $s.Envs -SourceId dev -TargetId test 6>$null) 6>$null
        $run = (Invoke-CcTestRun -Environments $s.Envs -SourceId dev -TargetId test -Selection (Get-CcSelection $plan)).Run
        $failed = @($run.items | Where-Object outcome -eq 'failed')
        $failed.displayName | Should -Be @('Mortgage queue')
        $failed[0].message | Should -Be 'A queue with this name already exists.'
        # The ruleset embeds the queue; the default-queue link points at it. Unrelated records still go.
        (@($run.items | Where-Object { $_.displayName -eq 'Mortgage route' }).outcome) | Should -Be 'skipped'
        (@($run.items | Where-Object { $_.displayName -eq 'Greeting' }).outcome) | Should -Be 'created'
        # Mortgage chat was created, but its default queue could not be linked: the check says so.
        $v = $run.verification
        $v.state | Should -Be 'Differences'
        @($v.differences).Count | Should -Be 1
        $v.differences[0].displayName | Should -Be 'Mortgage chat'
        "$($v.differences[0].fields[0].label)|$($v.differences[0].fields[0].source)|$($v.differences[0].fields[0].target)" | Should -Be "Default Queue|queue 'Mortgage queue'|(none)"
    }
}
