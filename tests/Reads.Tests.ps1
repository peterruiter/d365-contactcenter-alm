# What a compare read, reused: the plan check and the dry run after a compare read nothing from
# Dataverse, an apply re-reads only the target's records, and the results are the same as with
# fresh reads.

BeforeAll {
    . (Join-Path $PSScriptRoot 'support/TestSupport.ps1')

    function Get-CcReadCount($Org) { $Org.MetadataReads + $Org.RecordReads }
    function Get-CcSummaryText($Diff) { ($Diff.summary | ConvertTo-Json -Compress) }
}

Describe 'Reusing what a compare read' {
    BeforeAll {
        $s = New-CcSyntheticScenario
        Mount-CcFakeDataverse -Orgs $s.Dev, $s.Test | Out-Null
        $reads = New-CcReadCache
        $diff = Compare-CcConfig -Environments $s.Envs -SourceId dev -TargetId test -ReadCache $reads 6>$null
        # Through a file and back, as the hosts store it.
        $file = Join-Path ([IO.Path]::GetTempPath()) "ccalm-reads-$([guid]::NewGuid().ToString('N').Substring(0, 8)).json"
        Export-CcReadCache -Cache $reads -Path $file
        $stored = Import-CcReadCache -Path $file
        $plan = New-CcPlan -Diff $diff 6>$null
    }
    AfterAll { Remove-Item $file -ErrorAction SilentlyContinue }

    It 'keeps every read of the compare' {
        $stored | Should -Not -BeNullOrEmpty
        $stored.entries.Count | Should -Be $reads.entries.Count
        $stored.entries.Count | Should -Be ((Get-CcReadCount $s.Dev) + (Get-CcReadCount $s.Test))
    }

    It 'compares again from the stored reads without reading Dataverse, with the same result' {
        $before = (Get-CcReadCount $s.Dev) + (Get-CcReadCount $s.Test)
        $again = Compare-CcConfig -Environments $s.Envs -SourceId dev -TargetId test -ReadCache $stored 6>$null
        ((Get-CcReadCount $s.Dev) + (Get-CcReadCount $s.Test)) | Should -Be $before
        Get-CcSummaryText $again | Should -Be (Get-CcSummaryText $diff)
        $p2 = New-CcPlan -Diff $again 6>$null
        $p2.summary.ready | Should -Be $plan.summary.ready
        $p2.summary.blocked | Should -Be $plan.summary.blocked
    }

    It 'replays a table that is not installed as not installed' {
        $tables = @($diff.notices | Where-Object { $_.message -match 'not installed' })
        $again = Compare-CcConfig -Environments $s.Envs -SourceId dev -TargetId test -ReadCache $stored 6>$null
        @($again.notices | Where-Object { $_.message -match 'not installed' }).Count | Should -Be $tables.Count
    }

    It 'runs a dry run without reading Dataverse at all' {
        $before = (Get-CcReadCount $s.Dev) + (Get-CcReadCount $s.Test)
        $run = (Invoke-CcTestRun -Environments $s.Envs -SourceId dev -TargetId test -Mode dryRun -Selection (Get-CcSelection $plan) -Reads $stored).Run
        ((Get-CcReadCount $s.Dev) + (Get-CcReadCount $s.Test)) | Should -Be $before
        $run.summary.failed | Should -Be 0
        $run.summary.created | Should -BeGreaterThan 0
        $s.Test.Writes.Count | Should -Be 0
    }
}

Describe 'An apply from stored reads' {
    BeforeAll {
        $s = New-CcSyntheticScenario
        Mount-CcFakeDataverse -Orgs $s.Dev, $s.Test | Out-Null
        $reads = New-CcReadCache
        $diff = Compare-CcConfig -Environments $s.Envs -SourceId dev -TargetId test -ReadCache $reads 6>$null
        $plan = New-CcPlan -Diff $diff 6>$null

        # Someone adds a tag to Test after the compare and before the apply.
        Add-CcFakeRecord $s.Test msdyn_octag @{ msdyn_name = 'Escalated' } | Out-Null

        $devReads = Get-CcReadCount $s.Dev
        $testMeta = $s.Test.MetadataReads
        $testRecords = $s.Test.RecordReads
        $run = (Invoke-CcTestRun -Environments $s.Envs -SourceId dev -TargetId test -Mode apply -Selection (Get-CcSelection $plan) -Reads $reads).Run
    }

    It 'reads nothing from the source and no metadata, only the target records' {
        Get-CcReadCount $s.Dev | Should -Be $devReads
        $s.Test.MetadataReads | Should -Be $testMeta
        $s.Test.RecordReads | Should -BeGreaterThan $testRecords
    }

    It 'writes from the target as it is now, not as it was at the compare' {
        @($s.Test.Tables['msdyn_octag'].Rows | Where-Object msdyn_name -eq 'Escalated').Count | Should -Be 1
        @($run.items | Where-Object { $_.table -eq 'msdyn_octag' -and $_.displayName -eq 'Escalated' }).Count | Should -Be 0
    }

    It 'ends the same as an apply from fresh reads' {
        $run.summary.failed | Should -Be 0
        $run.summary.blocked | Should -Be 2
        $run.verification.state | Should -Be 'Verified'
    }
}

Describe 'Stored reads that cannot be used' {
    It 'are ignored when too old, missing or broken' {
        $file = Join-Path ([IO.Path]::GetTempPath()) "ccalm-reads-$([guid]::NewGuid().ToString('N').Substring(0, 8)).json"
        try {
            Import-CcReadCache -Path $file | Should -BeNullOrEmpty
            Set-Content $file 'not json'
            Import-CcReadCache -Path $file | Should -BeNullOrEmpty
            $old = New-CcReadCache
            $old.takenAt = (Get-Date).AddHours(-2).ToString('o')
            Export-CcReadCache -Cache $old -Path $file
            Import-CcReadCache -Path $file -MaxAgeMinutes 60 | Should -BeNullOrEmpty
            Import-CcReadCache -Path $file -MaxAgeMinutes 180 | Should -Not -BeNullOrEmpty
        }
        finally { Remove-Item $file -ErrorAction SilentlyContinue }
    }
}
