function Get-CcDetectOnly {
    <#
    .SYNOPSIS
        Flags configuration that cannot move as data: ACS phone numbers, Copilot Studio agents,
        channel accounts. Reports each source record carrying the signal whose matching target record
        does not carry it yet.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [pscustomobject] $Manifest,
        [Parameter(Mandatory)] [pscustomobject] $Source,
        [Parameter(Mandatory)] [pscustomobject] $Target,
        [Parameter(Mandatory)] [hashtable] $TablePlans
    )

    $findings = [System.Collections.Generic.List[object]]::new()
    foreach ($rule in @($Manifest.detectOnly)) {
        if (-not $rule) { continue }
        $plan = $TablePlans[$rule.logicalName]
        if (-not $plan -or -not $plan.Usable) { continue }
        $signalCols = @($rule.signal, "_$($rule.signal)_value")

        foreach ($id in $Source.ById[$rule.logicalName].Keys) {
            $row = $Source.ById[$rule.logicalName][$id]
            if ($row.ismanaged -eq $true) { continue }
            $hasSignal = @($signalCols | Where-Object { $row.PSObject.Properties.Name -contains $_ -and $row.$_ }).Count -gt 0
            if (-not $hasSignal) { continue }

            $key = $Source.KeyById[$rule.logicalName][$id]
            $tgt = Get-CcRecordByKey -Env $Target -Table $rule.logicalName -Key $key
            if ($tgt -and @($signalCols | Where-Object { $tgt.PSObject.Properties.Name -contains $_ -and $tgt.$_ }).Count -gt 0) { continue }

            $findings.Add([pscustomobject]@{
                    type    = $rule.type
                    table   = $rule.logicalName
                    label   = Get-CcTableLabel $plan.Table
                    record  = Get-CcRecordLabel -Record $row -TablePlan $plan
                    message = $rule.message
                }) | Out-Null
        }
    }
    return $findings
}
