# Unit tests of the engine's small, pure pieces: value comparison, GUID rewriting, keys, errors,
# stale runs.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../backend/function-app/Modules/CcAlm/CcAlm.psd1') -Force -DisableNameChecking
}

Describe 'Comparing values' {
    It 'treats <a> and <b> as <same>' -ForEach @(
        @{ a = $null; b = ''; same = $true }
        @{ a = 1; b = '1'; same = $true }
        @{ a = $true; b = 'True'; same = $true }
        @{ a = 'Queue'; b = 'queue'; same = $false }
        @{ a = 'x'; b = $null; same = $false }
    ) {
        InModuleScope CcAlm -Parameters @{ a = $a; b = $b } { param($a, $b) Test-CcSameValue $a $b } | Should -Be $same
    }
}

Describe 'GUIDs inside definitions' {
    It 'rewrites every known GUID whatever its case, and reports the ones it cannot map' {
        InModuleScope CcAlm {
            $q = '11111111-2222-3333-4444-555555555555'
            $s = '99999999-8888-7777-6666-555555555555'
            $other = 'abcdefab-cdef-abcd-efab-cdefabcdefab'
            $srcMap = @{ $q = @{ Entity = 'queue'; Key = 'name=billing' }; $s = @{ Entity = 'characteristic'; Key = 'name=gone' } }
            $tgt = @{ 'queue|name=billing' = 'aaaaaaaa-0000-0000-0000-000000000001' }
            $r = ConvertTo-CcTargetDefinition -Definition "<r q=`"$($q.ToUpperInvariant())`" s=`"$s`" t=`"$other`"/>" -SourceGuidToRef $srcMap -TargetKeyToGuid $tgt
            $r.Text | Should -Be "<r q=`"aaaaaaaa-0000-0000-0000-000000000001`" s=`"$s`" t=`"$other`"/>"
            @($r.Unmapped).Count | Should -Be 1
            $r.Unmapped[0].Key | Should -Be 'name=gone'
        }
    }

    It 'normalises two definitions that point at the same records to the same text' {
        InModuleScope CcAlm {
            $a = ConvertTo-CcNormalisedDefinition -Definition '<r q="11111111-2222-3333-4444-555555555555"/>' -GuidToRef @{ '11111111-2222-3333-4444-555555555555' = @{ Entity = 'queue'; Key = 'k' } }
            $b = ConvertTo-CcNormalisedDefinition -Definition '<r q="AAAAAAAA-2222-3333-4444-555555555555"/>' -GuidToRef @{ 'aaaaaaaa-2222-3333-4444-555555555555' = @{ Entity = 'queue'; Key = 'k' } }
            $a.Text | Should -Be $b.Text
            $a.Refs | Should -Be @('queue|k')
        }
    }
}

Describe 'Error messages' {
    It 'keeps only what Dataverse said' {
        InModuleScope CcAlm {
            # Dataverse sends apostrophes as a JSON unicode escape; built here so this file holds none.
            $raw = 'Web API Post https://x/api/data/v9.2/queues failed with 400. {"error":{"code":"0x1","message":"A queue named ~Billing~ already exists."}}' -creplace '~', ([string][char]92 + 'u0027')
            Get-CcErrorMessage $raw |
                Should -Be "A queue named 'Billing' already exists."
            Get-CcErrorMessage 'Web API Get https://x/y failed with 401. Unauthorized' | Should -Be 'Unauthorized'
            Get-CcErrorMessage '' | Should -Be 'Unknown error.'
        }
    }
}

Describe 'Stale runs' {
    It 'calls a run stale only when it is in progress and silent for longer than the limit' {
        $old = (Get-Date).AddMinutes(-30)
        Test-CcRunStale @{ state = 'Running'; updatedAt = $old } | Should -BeTrue
        Test-CcRunStale @{ state = 'Running'; updatedAt = $old.ToString('o') } | Should -BeTrue
        Test-CcRunStale @{ state = 'Running'; updatedAt = [datetimeoffset]$old } | Should -BeTrue
        Test-CcRunStale @{ state = 'Running'; updatedAt = (Get-Date).AddMinutes(-1).ToString('o') } | Should -BeFalse
        Test-CcRunStale @{ state = 'Succeeded'; updatedAt = $old } | Should -BeFalse
        Test-CcRunStale @{ state = 'Running'; updatedAt = 'not a date' } | Should -BeFalse
        Test-CcRunStale @{ state = 'Running' } | Should -BeFalse
    }

    It 'reads a run saved as JSON the same way' {
        $json = @{ state = 'Queued'; updatedAt = (Get-Date).AddHours(-1).ToString('o') } | ConvertTo-Json | ConvertFrom-Json
        Test-CcRunStale $json | Should -BeTrue
    }
}

Describe 'Run records' {
    It 'starts queued with an empty summary and the selection it was asked for' {
        $r = New-CcRunRecord -SourceId dev -TargetId test -Mode apply -Selection @(@{ table = 'queue'; matchKey = 'k' }) -Approved $true
        $r.state | Should -Be 'Queued'
        $r.runId | Should -Match '^run_[0-9a-f]{12}$'
        $r.request.selection[0].matchKey | Should -Be 'k'
        $r.request.approved | Should -BeTrue
        $r.summary.created | Should -Be 0
    }
}
