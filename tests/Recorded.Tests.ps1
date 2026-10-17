# Replays every recording in tests/fixtures/recorded (scripts/record-fixture.ps1) against the
# in-memory Dataverse: real configuration from real environments, without a network. Recordings
# are never committed, so on a fresh clone these tests are skipped.

BeforeDiscovery {
    . (Join-Path $PSScriptRoot 'support/TestSupport.ps1')
    $fixtures = @(Get-CcRecordedFixtures)
}

BeforeAll {
    . (Join-Path $PSScriptRoot 'support/TestSupport.ps1')
}

Describe 'Recorded fixtures' -Skip:($fixtures.Count -eq 0) {
    It 'has at least one recording (record one with scripts/record-fixture.ps1)' { $true | Should -BeTrue }
}

# Pester refuses -ForEach over an empty list, so the per-recording tests exist only when there is one.
if ($fixtures.Count -gt 0) {
Describe 'Recording <Name>' -ForEach $fixtures {
    BeforeAll {
        $f = Import-CcRecordedFixture -Path $Path
        $before = Copy-CcFakeOrg $f.Target -Url 'https://target-before.recorded.example'
        Mount-CcFakeDataverse -Orgs $f.Source, $f.Target, $before | Out-Null
        $diff = Compare-CcConfig -Environments $f.Envs -SourceId source -TargetId target 6>$null
        $plan = New-CcPlan -Diff $diff 6>$null
    }

    It 'compares the way it did when it was recorded' {
        foreach ($k in 'missingInTarget', 'extraInTarget', 'changed', 'equal', 'ambiguous') {
            $diff.summary.$k | Should -Be $f.Baseline.summary.$k -Because "the $k count was $($f.Baseline.summary.$k) when recorded"
        }
        foreach ($t in $diff.tables) {
            $now = @{}; foreach ($g in @($t.records | Group-Object status)) { $now[$g.Name] = $g.Count }
            $then = $f.Baseline.byTable.($t.table)
            foreach ($p in @($then.PSObject.Properties)) { $now[$p.Name] | Should -Be $p.Value -Because "$($t.table) had $($p.Value) $($p.Name) when recorded" }
        }
    }

    It 'plans the way it did when it was recorded' {
        $plan.summary.ready | Should -Be $f.Baseline.plan.ready
        $plan.summary.blocked | Should -Be $f.Baseline.plan.blocked
    }

    It 'gives every dependency a real record' {
        $deps = @($diff.tables | ForEach-Object { $_.records } | ForEach-Object { $_.dependsOn })
        @($deps | Where-Object { -not $_ -or -not $_.table -or -not $_.matchKey }).Count | Should -Be 0
        @($plan.operations | ForEach-Object { $_.blockers } | Where-Object { $_.message -match 'Needs a ,' }).Count | Should -Be 0
    }

    It 'finds nothing to move between the source and itself' {
        $self = @((New-CcFakeEnvironment a A $f.Source), (New-CcFakeEnvironment b B $f.Source))
        $d = Compare-CcConfig -Environments $self -SourceId a -TargetId b 6>$null
        $d.summary.missingInTarget + $d.summary.changed + $d.summary.extraInTarget | Should -Be 0
    }

    Context 'Dry run' {
        BeforeAll {
            $dry = (Invoke-CcTestRun -Environments $f.Envs -SourceId source -TargetId target -Mode dryRun -Selection (Get-CcSelection $plan)).Run
        }
        It 'writes nothing and fails nothing' {
            $f.Target.Writes.Count | Should -Be 0
            $dry.summary.failed | Should -Be 0
            $dry.summary.skipped | Should -Be 0
        }
    }

    Context 'Apply into a copy of the target, check, roll back' {
        BeforeAll {
            $result = Invoke-CcTestRun -Environments $f.Envs -SourceId source -TargetId target -Mode apply -Selection (Get-CcSelection $plan)
            $run = $result.Run
        }

        It 'writes every ready record and fails none' {
            $run.summary.failed | Should -Be 0
            $run.summary.skipped | Should -Be 0
            $run.summary.blocked | Should -Be $plan.summary.blocked
        }

        It 'finds every written record the same as the source afterwards, or says why not' {
            $v = $run.verification
            $v.checked | Should -BeGreaterThan 0
            $unexplained = @($v.differences | Where-Object { $_.status -ne 'Changed' -or @($_.fields | Where-Object { -not $_.note }).Count -gt 0 })
            $unexplained | ForEach-Object { Write-Host "  differs: $($_.tableLabel) '$($_.displayName)' $($_.status) $(@($_.fields | ForEach-Object label) -join ', ')" }
            $unexplained.Count | Should -Be 0
            @($v.added).Count | Should -Be 0
        }

        It 'puts the target back exactly as it was when rolled back' {
            $store = @{ Run = $run }
            Invoke-CcRollbackJob -Environments $f.Envs -SnapshotPath $result.SnapshotPath -LoadRun { $store.Run | ConvertTo-Json -Depth 40 | ConvertFrom-Json } -SaveRun { param($r) $store.Run = $r }
            $store.Run.state | Should -Be 'RolledBack'
            @($store.Run.cleanup.unresolved).Count | Should -Be 0
            $envs = @((New-CcFakeEnvironment before Before $before), (New-CcFakeEnvironment target Target $f.Target))
            $d = Compare-CcConfig -Environments $envs -SourceId before -TargetId target 6>$null
            $d.summary.missingInTarget + $d.summary.extraInTarget + $d.summary.changed | Should -Be 0
        }
    }
}
}
