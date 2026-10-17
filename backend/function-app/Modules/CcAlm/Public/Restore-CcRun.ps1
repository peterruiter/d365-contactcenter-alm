function Restore-CcRun {
    <#
    .SYNOPSIS
        Undoes an applied run from its snapshot: writes the recorded state back onto every record the
        run changed (settings and lookups), then deletes the records the run created, children before
        parents. Side-effects Dataverse provisions on its own (a created workstream's routing
        configuration) go with their parent where Dataverse cascades the delete; anything it refuses
        is reported, not hidden.
    .EXAMPLE
        Restore-CcRun -SnapshotPath ./out/snapshot-run_abc.json -Environments $envs
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $SnapshotPath,
        [Parameter(Mandatory)] [object[]] $Environments,
        [bool] $DeleteCreated = $true
    )

    if (-not (Test-Path $SnapshotPath)) { throw "Snapshot not found at $SnapshotPath" }
    $snapshot = Get-Content -Path $SnapshotPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $target = $Environments | Where-Object Id -eq $snapshot.environment | Select-Object -First 1
    if (-not $target) { throw "The snapshot is for '$($snapshot.environment)', which is not connected." }

    $restored = 0
    $deleted = 0
    $unlinked = 0
    $unresolved = [System.Collections.Generic.List[string]]::new()

    foreach ($e in @($snapshot.updated)) {
        if (-not $e) { continue }
        $body = [ordered]@{}
        foreach ($p in $e.data.PSObject.Properties) { $body[$p.Name] = $p.Value }
        foreach ($p in $e.binds.PSObject.Properties) { if ($p.Value) { $body["$($p.Name)@odata.bind"] = $p.Value } }
        if (-not $PSCmdlet.ShouldProcess("$($e.table) $($e.id) in $($target.Name)", 'restore')) { continue }
        try {
            Invoke-CcWebApi -Environment $target -Method Patch -Path "$($e.entitySet)($($e.id))" -Body $body -Prefer $null | Out-Null
            # A lookup that was empty before the run is cleared again.
            foreach ($p in $e.binds.PSObject.Properties) {
                if ($p.Value) { continue }
                try { Invoke-CcWebApi -Environment $target -Method Delete -Path "$($e.entitySet)($($e.id))/$($p.Name)/`$ref" -Prefer $null | Out-Null } catch { }
            }
            $restored++
        }
        catch {
            $unresolved.Add("Could not restore $($e.table) $($e.id): $(Get-CcErrorMessage $_.Exception.Message)") | Out-Null
        }
    }

    # Links the run made between records that stay; links to records about to be deleted go with them.
    foreach ($a in @($snapshot.associated | Where-Object { $_ })) {
        if (-not $PSCmdlet.ShouldProcess("link $($a.label) in $($target.Name)", 'unlink')) { continue }
        try {
            Invoke-CcWebApi -Environment $target -Method Delete -Path "$($a.entitySet)($($a.id))/$($a.nav)($($a.otherId))/`$ref" -Prefer $null | Out-Null
            $unlinked++
        }
        catch {
            $msg = Get-CcErrorMessage $_.Exception.Message
            if ($msg -match 'does not exist|404') { $unlinked++; continue }
            $unresolved.Add("Could not unlink $($a.label): $msg") | Out-Null
        }
    }

    if ($DeleteCreated) {
        foreach ($c in @($snapshot.created | Where-Object { $_ } | Sort-Object { [int]$_.order } -Descending)) {
            if (-not $PSCmdlet.ShouldProcess("$($c.table) '$($c.label)' in $($target.Name)", 'delete')) { continue }
            try {
                Invoke-CcWebApi -Environment $target -Method Delete -Path "$($c.entitySet)($($c.id))" -Prefer $null | Out-Null
                $deleted++
            }
            catch {
                $msg = Get-CcErrorMessage $_.Exception.Message
                if ($msg -match 'does not exist|404') { $deleted++; continue }   # already gone with its parent
                $unresolved.Add("Could not delete '$($c.label)' ($($c.table)): $msg") | Out-Null
            }
        }
    }

    $result = [pscustomobject]@{
        state      = 'RolledBack'
        restored   = $restored
        deleted    = $deleted
        unlinked   = $unlinked
        unresolved = @($unresolved)
    }
    Write-Host "Rollback: $restored records restored, $deleted created records deleted, $($unresolved.Count) not resolved." -ForegroundColor Cyan
    foreach ($u in $unresolved) { Write-Host "  - $u" -ForegroundColor Yellow }
    return $result
}
