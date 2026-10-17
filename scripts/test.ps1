<#
.SYNOPSIS
    Runs the engine's tests: unit tests, the synthetic Dev-to-Test scenario, and every recording in
    tests/fixtures/recorded. No network, no environment, nothing written anywhere.
.EXAMPLE
    ./scripts/test.ps1
.EXAMPLE
    ./scripts/test.ps1 -Path tests/Scenario.Tests.ps1
#>
#Requires -Version 7.2
param(
    [string[]] $Path = @(Join-Path (Split-Path $PSScriptRoot -Parent) 'tests'),
    [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')] [string] $Output = 'Detailed'
)

$pester = Get-Module -ListAvailable Pester | Where-Object Version -ge ([version]'5.5.0') | Sort-Object Version -Descending | Select-Object -First 1
if (-not $pester) {
    Write-Host 'The tests need Pester 5.5 or later. Install it with:' -ForegroundColor Yellow
    Write-Host '  Install-Module Pester -Scope CurrentUser -Force -SkipPublisherCheck'
    exit 1
}
Import-Module $pester.Path -Force

$config = New-PesterConfiguration
$config.Run.Path = $Path
$config.Run.Exit = $true
$config.Output.Verbosity = $Output
Invoke-Pester -Configuration $config
