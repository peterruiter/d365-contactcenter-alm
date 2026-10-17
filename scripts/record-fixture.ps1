<#
.SYNOPSIS
    Records a compare between two real environments as an offline test fixture.
.DESCRIPTION
    Runs the engine's own compare against both environments, read-only, and saves every metadata
    and record response it receives to tests/fixtures/recorded/<Name>. The regression tests then
    replay it against an in-memory Dataverse: compare, plan, dry run, apply into the fake target,
    verify and roll back, all without a network.

    Sign-in uses your own Azure CLI login (az login), not an app registration, so it reads with your
    rights. Nothing is written to either environment.

    Recordings hold real configuration (names, settings, GUIDs). tests/fixtures/recorded is in
    .gitignore; keep it that way and never commit one.
.EXAMPLE
    ./scripts/record-fixture.ps1 -Name dev-test -SourceUrl https://contoso-dev.crm4.dynamics.com -TargetUrl https://contoso-test.crm4.dynamics.com
.EXAMPLE
    ./scripts/record-fixture.ps1 -Name dev-test -SourceUrl ... -TargetUrl ... -Subscription 00000000-0000-0000-0000-000000000000
#>
#Requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [ValidatePattern('^[a-z0-9][a-z0-9-]*$')] [string] $Name,
    [Parameter(Mandatory)] [string] $SourceUrl,
    [Parameter(Mandatory)] [string] $TargetUrl,
    # The az subscription whose login can read both environments, when it is not the default.
    [string] $Subscription,
    [string] $SourceName = 'Source',
    [string] $TargetName = 'Target'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$outDir = Join-Path $root "tests/fixtures/recorded/$Name"
Import-Module (Join-Path $root 'backend/function-app/Modules/CcAlm/CcAlm.psd1') -Force
$module = Get-Module CcAlm

# Inside the module: tokens from az instead of client credentials, and every GET recorded.
& $module {
    param($Subscription)
    $script:CcRecTokens = @{}
    $script:CcRecSubscription = $Subscription
    $script:CcRecording = @{}
    $script:CcRecOriginal = ${function:Invoke-CcWebApi}

    function script:Get-CcToken {
        param($TenantId, $ClientId, $ClientSecret, $ResourceUrl)
        $resource = $ResourceUrl.TrimEnd('/')
        if (-not $script:CcRecTokens[$resource]) {
            $azArgs = @('account', 'get-access-token', '--resource', $resource, '--query', 'accessToken', '-o', 'tsv')
            if ($script:CcRecSubscription) { $azArgs += @('--subscription', $script:CcRecSubscription) }
            $token = & az @azArgs
            if ($LASTEXITCODE -ne 0 -or -not $token) { throw "az could not get a token for $resource. Run az login first." }
            $script:CcRecTokens[$resource] = $token
        }
        return $script:CcRecTokens[$resource]
    }

    function script:Invoke-CcWebApi {
        param($Environment, $Method, $Path, $Body, $ExtraHeaders, $Prefer = 'odata.include-annotations="*"', $MaxRetries = 6)
        if ($Method -ne 'Get') { throw "The recorder only reads. Refused: $Method $Path" }
        $rec = $script:CcRecording[$Environment.Id]
        if (-not $rec) { $rec = @{ metadata = [ordered]@{}; records = [ordered]@{} }; $script:CcRecording[$Environment.Id] = $rec }

        $isMeta = $Path -match "^EntityDefinitions\(LogicalName='([^']+)'\)"
        $logical = if ($isMeta) { $Matches[1] } else { $null }
        try {
            $res = & $script:CcRecOriginal -Environment $Environment -Method $Method -Path $Path -Body $Body -ExtraHeaders $ExtraHeaders -Prefer $Prefer -MaxRetries $MaxRetries
        }
        catch {
            if ($isMeta) { $rec.metadata[$logical] = $null }
            throw
        }
        if ($isMeta) { $rec.metadata[$logical] = $res }
        else {
            $relative = $Path -replace '^https?://[^/]+/api/data/v[\d.]+/', ''
            $set = ($relative -split '\?', 2)[0]
            if (-not $rec.records.Contains($set)) { $rec.records[$set] = [System.Collections.Generic.List[object]]::new() }
            foreach ($r in @($res.value)) { if ($r) { $rec.records[$set].Add($r) } }
        }
        return $res
    }
} $Subscription

$envs = @(
    [pscustomobject]@{ Id = 'source'; Name = $SourceName; Url = $SourceUrl.TrimEnd('/'); Role = 'any'; RequireApproval = $false; ApiVersion = 'v9.2'; TenantId = 'az'; ClientId = 'az'; ClientSecret = 'az' }
    [pscustomobject]@{ Id = 'target'; Name = $TargetName; Url = $TargetUrl.TrimEnd('/'); Role = 'any'; RequireApproval = $false; ApiVersion = 'v9.2'; TenantId = 'az'; ClientId = 'az'; ClientSecret = 'az' }
)

Write-Host "Reading $SourceName and $TargetName (read-only)..."
$diff = Compare-CcConfig -Environments $envs -SourceId source -TargetId target 6>$null
$plan = New-CcPlan -Diff $diff 6>$null

if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$recording = & $module { $script:CcRecording }
foreach ($side in 'source', 'target') {
    $recording[$side].metadata | ConvertTo-Json -Depth 50 -Compress | Set-Content (Join-Path $outDir "$side.metadata.json") -Encoding utf8NoBOM
    $recording[$side].records | ConvertTo-Json -Depth 50 -Compress | Set-Content (Join-Path $outDir "$side.records.json") -Encoding utf8NoBOM
}

# What this compare and plan found, so a later engine change that shifts them shows up in the tests.
$baseline = [ordered]@{
    recordedAt = (Get-Date).ToString('o')
    source     = @{ name = $SourceName; url = $SourceUrl }
    target     = @{ name = $TargetName; url = $TargetUrl }
    summary    = $diff.summary
    byTable    = [ordered]@{}
    plan       = [ordered]@{
        ready    = $plan.summary.ready
        blocked  = $plan.summary.blocked
        blockers = @($plan.operations | Where-Object status -eq 'blocked' | ForEach-Object { $_.blockers } | ForEach-Object { $_.code } | Group-Object | Sort-Object Name | ForEach-Object { [ordered]@{ code = $_.Name; count = $_.Count } })
    }
    detectOnly = @($diff.detectOnly).Count
}
foreach ($t in $diff.tables) {
    $baseline.byTable[$t.table] = [ordered]@{}
    foreach ($g in @($t.records | Group-Object status | Sort-Object Name)) { $baseline.byTable[$t.table][$g.Name] = $g.Count }
}
$baseline | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $outDir 'baseline.json') -Encoding utf8NoBOM

$size = [math]::Round(((Get-ChildItem $outDir | Measure-Object Length -Sum).Sum / 1MB), 1)
Write-Host "Recorded $Name in $outDir ($size MB). Do not commit it: it holds real configuration." -ForegroundColor Green
