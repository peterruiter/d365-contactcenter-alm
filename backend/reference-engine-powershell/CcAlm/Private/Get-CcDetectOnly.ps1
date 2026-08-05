function Get-CcDetectOnly {
    <#
    .SYNOPSIS
        Flags config that cannot move as data: ACS phone numbers, bots, channel accounts.
        Reads the source records for each detect rule and reports where the target lacks the equivalent.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [pscustomobject] $Manifest,
        [Parameter(Mandatory)] [hashtable] $SourceRecordsByTable,
        [Parameter(Mandatory)] [hashtable] $TargetRecordsByTable
    )

    $findings = [System.Collections.Generic.List[object]]::new()
    if (-not $Manifest.detectOnly) { return $findings }

    function Test-CcSignal {
        param($Row, $SignalCol)
        $valueCol = "_$($SignalCol)_value"
        if ($Row.PSObject.Properties.Name -contains $SignalCol -and $Row.$SignalCol) { return $true }
        if ($Row.PSObject.Properties.Name -contains $valueCol -and $Row.$valueCol) { return $true }
        return $false
    }

    foreach ($rule in $Manifest.detectOnly) {
        $sourceRows = $SourceRecordsByTable[$rule.logicalName]
        if (-not $sourceRows) { continue }
        $targetRows = $TargetRecordsByTable[$rule.logicalName]

        # Index target rows by name so we can tell whether the target already carries the signal.
        $targetByName = @{}
        foreach ($tr in $targetRows) {
            if ($tr.PSObject.Properties.Name -contains 'msdyn_name' -and $tr.msdyn_name) {
                $targetByName["$($tr.msdyn_name)".ToLowerInvariant()] = $tr
            }
        }

        foreach ($row in $sourceRows) {
            if (-not (Test-CcSignal -Row $row -SignalCol $rule.signal)) { continue }

            $label = if ($row.PSObject.Properties.Name -contains 'msdyn_name') { $row.msdyn_name } else { $rule.logicalName }

            # If the matching target record already carries the signal, it is provisioned. Skip it.
            $key = if ($label) { "$label".ToLowerInvariant() } else { $null }
            if ($key -and $targetByName.ContainsKey($key) -and (Test-CcSignal -Row $targetByName[$key] -SignalCol $rule.signal)) {
                continue
            }

            $findings.Add([pscustomobject]@{
                type    = $rule.type
                table   = $rule.logicalName
                record  = $label
                message = $rule.message
            }) | Out-Null
        }
    }

    return $findings
}
