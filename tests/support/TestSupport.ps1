# Shared by the test files: the fake Dataverse, the synthetic scenario, recorded fixtures, and a
# helper that runs a background run job to the end with in-memory storage.

. (Join-Path $PSScriptRoot 'FakeDataverse.ps1')
. (Join-Path $PSScriptRoot 'SyntheticScenario.ps1')

function Get-CcRecordedFixtures {
    # Every recording in tests/fixtures/recorded, for -ForEach. Empty when there are none.
    $dir = Join-Path $PSScriptRoot '../fixtures/recorded'
    if (-not (Test-Path $dir)) { return @() }
    return @(Get-ChildItem $dir -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'baseline.json') } |
            ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } })
}

function Import-CcRecordedFixture {
    # A recording as two fake orgs, plus what the compare found when it was recorded.
    param([Parameter(Mandatory)] [string] $Path)
    $load = {
        param($side)
        $meta = Get-Content (Join-Path $Path "$side.metadata.json") -Raw | ConvertFrom-Json -AsHashtable
        $m = @{}
        foreach ($k in $meta.Keys) { $m[$k] = if ($meta[$k]) { $meta[$k] | ConvertTo-Json -Depth 30 -Compress | ConvertFrom-Json } else { $null } }
        $rec = Get-Content (Join-Path $Path "$side.records.json") -Raw | ConvertFrom-Json
        $r = @{}
        foreach ($p in $rec.PSObject.Properties) { $r[$p.Name] = @($p.Value) }
        New-CcFakeOrg -Url "https://$side.recorded.example" -Metadata $m -Records $r
    }
    $source = & $load 'source'
    $target = & $load 'target'
    [pscustomobject]@{
        Source   = $source
        Target   = $target
        Baseline = Get-Content (Join-Path $Path 'baseline.json') -Raw | ConvertFrom-Json
        Envs     = @(
            New-CcFakeEnvironment -Id 'source' -Name 'Source' -Org $source
            New-CcFakeEnvironment -Id 'target' -Name 'Target' -Org $target
        )
    }
}

function Invoke-CcTestRun {
    <#
    .SYNOPSIS
        Starts a background run the way the hosts do and runs it slice by slice until it is done,
        with the run and its snapshot kept in memory. Returns the final run, the snapshot (also
        written to a file, for rollback) and how many slices it took.
    #>
    param(
        [Parameter(Mandatory)] [object[]] $Environments,
        [Parameter(Mandatory)] [string] $SourceId,
        [Parameter(Mandatory)] [string] $TargetId,
        [ValidateSet('apply', 'dryRun')] [string] $Mode = 'apply',
        [object[]] $Selection,
        [int] $TimeBudgetSeconds = 0,
        [int] $MaxSlices = 50
    )
    $work = Join-Path ([IO.Path]::GetTempPath()) "ccalm-tests-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    $store = @{
        Run  = New-CcRunRecord -SourceId $SourceId -TargetId $TargetId -Mode $Mode -Selection $Selection -Approved $true
        Snap = $null
    }
    $slices = 0
    do {
        $slices++
        # Each slice reads the run back from JSON, as the hosts do from a file or a blob.
        $res = Invoke-CcRunJob -Environments $Environments -TimeBudgetSeconds $TimeBudgetSeconds -WorkDir $work `
            -LoadRun { $store.Run | ConvertTo-Json -Depth 40 | ConvertFrom-Json } `
            -SaveRun { param($r) $store.Run = $r } `
            -LoadSnapshot { if ($store.Snap) { $store.Snap | ConvertTo-Json -Depth 40 | ConvertFrom-Json } } `
            -SaveSnapshot { param($s) $store.Snap = $s }
    } while ($res.Continue -and $slices -lt $MaxSlices)

    $snapPath = $null
    if ($store.Snap) {
        $snapPath = Join-Path $work 'snapshot.json'
        $store.Snap | ConvertTo-Json -Depth 40 | Set-Content $snapPath -Encoding utf8NoBOM
    }
    [pscustomobject]@{ Run = $store.Run; Snapshot = $store.Snap; SnapshotPath = $snapPath; Slices = $slices; Finished = -not $res.Continue }
}

function Get-CcDiffRow {
    # One record of a diff by table and display name (and context, when names repeat).
    param($Diff, [string] $Table, [string] $Name, [string] $Context)
    $rows = @($Diff.tables | Where-Object table -eq $Table | ForEach-Object { $_.records } | Where-Object displayName -eq $Name)
    if ($PSBoundParameters.ContainsKey('Context')) { $rows = @($rows | Where-Object context -eq $Context) }
    return $rows
}

function Get-CcAllRows {
    param($Diff)
    return @($Diff.tables | ForEach-Object { $t = $_.table; $_.records | ForEach-Object { $_ | Add-Member -NotePropertyName table -NotePropertyValue $t -Force -PassThru } })
}

function Get-CcSelection {
    # Every operation of a plan as a selection, the way the app sends an apply.
    param($Plan)
    return @($Plan.operations | ForEach-Object { @{ table = $_.table; matchKey = $_.matchKey } })
}
