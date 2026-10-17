function New-CcReadCache {
    <#
    .SYNOPSIS
        An empty cache of Dataverse reads for Compare-CcConfig -ReadCache. Compare fills it; a plan
        check, dry run or apply started from the same compare passes it again and reads nothing (or,
        for an apply, only the target's records) from Dataverse.
    .EXAMPLE
        $reads = New-CcReadCache
        $diff = Compare-CcConfig -Environments $envs -SourceId dev -TargetId test -ReadCache $reads
        Export-CcReadCache -Cache $reads -Path ./out/reads.json
    #>
    [CmdletBinding()]
    param()
    [pscustomobject]@{ version = 1; takenAt = (Get-Date).ToString('o'); entries = @{} }
}
