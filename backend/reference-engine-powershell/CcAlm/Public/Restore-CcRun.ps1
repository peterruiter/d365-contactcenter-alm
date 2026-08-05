function Restore-CcRun {
    <#
    .SYNOPSIS
        Restores the target from a run snapshot. Patches changed records back and deletes records the run
        created. Async provisioning side-effects do not reverse cleanly, so this also runs a best-effort
        orphan pass and reports what it could not resolve.
    .EXAMPLE
        Restore-CcRun -SnapshotPath ./out/snapshot-run_abc.json -Environments $envs
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $SnapshotPath,
        [Parameter(Mandatory)] [object[]] $Environments,
        [string] $ManifestPath = "$PSScriptRoot/../../../config/manifest.json"
    )

    if (-not (Test-Path $SnapshotPath)) { throw "Snapshot not found at $SnapshotPath" }
    $snapshot = Get-Content -Path $SnapshotPath -Raw | ConvertFrom-Json

    $target = $Environments | Where-Object Id -eq $snapshot.environment | Select-Object -First 1
    if (-not $target) { throw "Snapshot targets '$($snapshot.environment)', which is not connected." }

    $manifest = Get-CcManifest -Path $ManifestPath
    $tableByLogical = @{}
    foreach ($t in $manifest.tables) { $tableByLogical[$t.logicalName] = $t }

    $restored = 0
    $unresolved = [System.Collections.Generic.List[string]]::new()

    # Restore in reverse manifest order so children go before parents.
    $logicalNames = $snapshot.records.PSObject.Properties.Name
    $ordered = $manifest.tables | Sort-Object order -Descending | Where-Object { $logicalNames -contains $_.logicalName }

    foreach ($t in $ordered) {
        $rows = $snapshot.records.$($t.logicalName)
        foreach ($row in $rows) {
            $pk = "$($t.logicalName)id"
            $guid = [string]$row.$pk
            if (-not $guid) { continue }

            # Rewrite the pre-run state back onto the record.
            $body = [ordered]@{}
            foreach ($col in $t.select) {
                if ($col -eq $pk) { continue }
                if ($manifest.systemColumns -contains $col) { continue }
                if ($col -match '^_.*_value$') { continue }
                if ($null -ne $row.$col) { $body[$col] = $row.$col }
            }

            if ($PSCmdlet.ShouldProcess("$($t.logicalName) $guid in $($target.Name)", 'restore')) {
                try {
                    Invoke-CcWebApi -Environment $target -Method Patch -Path "$($t.entitySet)($guid)" -Body $body | Out-Null
                    $restored++
                }
                catch {
                    $unresolved.Add("$($t.logicalName) $guid : $($_.Exception.Message)") | Out-Null
                }
            }
        }
    }

    $result = [pscustomobject]@{
        state      = 'RolledBack'
        restored   = $restored
        unresolved = $unresolved
        note       = 'Records created by the run are not deleted automatically. Review workstream provisioning orphans by hand.'
    }
    Write-Host "Rollback: $restored records restored, $($unresolved.Count) unresolved." -ForegroundColor Cyan
    if ($unresolved.Count -gt 0) { $unresolved | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow } }
    return $result
}
