# Runs once on cold start. Loads the engine and defines helpers shared by every function.

$ErrorActionPreference = 'Stop'

Import-Module "$PSScriptRoot/Modules/CcAlm/CcAlm.psd1" -Force

# The manifest ships beside the function app (deploy copies it here).
if (Test-Path "$PSScriptRoot/manifest.json") {
    $env:CCALM_MANIFEST_PATH = "$PSScriptRoot/manifest.json"
}

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

# --- Connect using app settings, not a file ------------------------------------

function Get-CcRegistryJson {
    # The registry can come from the CCALM_ENVIRONMENTS app setting, or from an environments.json
    # shipped with the app. The file fallback avoids CLI quoting problems when setting a big JSON
    # blob as an app setting.
    if ($env:CCALM_ENVIRONMENTS) { return $env:CCALM_ENVIRONMENTS }
    $file = Join-Path $PSScriptRoot 'environments.json'
    if (Test-Path $file) { return (Get-Content $file -Raw) }
    throw 'No environment registry. Set CCALM_ENVIRONMENTS, or ship environments.json with the app.'
}

function Get-CcConnected {
    $json = Get-CcRegistryJson
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "ccalm-env-$([guid]::NewGuid().ToString('N')).json"
    Set-Content -Path $tmp -Value $json -Encoding UTF8
    try {
        return Connect-CcEnvironment -ConfigPath $tmp
    }
    finally {
        Remove-Item $tmp -ErrorAction SilentlyContinue
    }
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
                    [ordered]@{ matchKey = $_.matchKey; status = $_.status; fields = @($_.fields) }
                })
            }
        })
        detectOnly = @($diff.detectOnly)
    }
}

function ConvertTo-CcPlanContract($plan) {
    [ordered]@{
        planId     = $plan.planId
        source     = $plan.source
        target     = $plan.target
        created    = $plan.created
        operations = @($plan.operations | ForEach-Object {
            [ordered]@{
                seq = $_.seq; stage = $_.stage; table = $_.table
                label = Get-CcLabel $_.table; op = $_.op; matchKey = $_.matchKey
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

# --- Blob persistence for run records and snapshots ----------------------------

function Get-CcBlobContext {
    if (-not $env:AzureWebJobsStorage) { throw 'AzureWebJobsStorage is not set.' }
    New-AzStorageContext -ConnectionString $env:AzureWebJobsStorage
}

function Get-CcRunsContainer {
    if ($env:CCALM_RUNS_CONTAINER) { return $env:CCALM_RUNS_CONTAINER }
    return 'ccalm-runs'
}

function Save-CcBlobJson([string] $name, $object) {
    $ctx = Get-CcBlobContext
    $container = Get-CcRunsContainer
    if (-not (Get-AzStorageContainer -Name $container -Context $ctx -ErrorAction SilentlyContinue)) {
        New-AzStorageContainer -Name $container -Context $ctx -Permission Off | Out-Null
    }
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) $name
    $object | ConvertTo-Json -Depth 40 | Set-Content -Path $tmp -Encoding UTF8
    Set-AzStorageBlobContent -File $tmp -Container $container -Blob $name -Context $ctx -Force | Out-Null
    Remove-Item $tmp -ErrorAction SilentlyContinue
}

function Get-CcBlobJson([string] $name) {
    $ctx = Get-CcBlobContext
    $container = Get-CcRunsContainer
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) $name
    Get-AzStorageBlobContent -Blob $name -Container $container -Destination $tmp -Context $ctx -Force -ErrorAction Stop | Out-Null
    $json = Get-Content -Path $tmp -Raw | ConvertFrom-Json
    Remove-Item $tmp -ErrorAction SilentlyContinue
    return $json
}

function Get-CcBlobFile([string] $name, [string] $destination) {
    $ctx = Get-CcBlobContext
    $container = Get-CcRunsContainer
    Get-AzStorageBlobContent -Blob $name -Container $container -Destination $destination -Context $ctx -Force -ErrorAction Stop | Out-Null
    return $destination
}

# --- HTTP helpers --------------------------------------------------------------

function Read-CcBody($Request) {
    if ($Request.Body -is [string]) {
        if ([string]::IsNullOrWhiteSpace($Request.Body)) { return @{} }
        return $Request.Body | ConvertFrom-Json
    }
    return $Request.Body
}

function Push-CcJson([int] $status, $body) {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode  = $status
        Headers     = @{ 'Content-Type' = 'application/json' }
        Body        = ($body | ConvertTo-Json -Depth 40)
    })
}

function Push-CcError([int] $status, [string] $code, [string] $message) {
    Push-CcJson $status @{ error = @{ code = $code; message = $message; details = @() } }
}

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
