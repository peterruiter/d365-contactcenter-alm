@{
    RootModule        = 'CcAlm.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'b7d2f4a1-9c3e-4a6b-8f21-2e5c7a9d0c11'
    Author            = 'Peter Ruiter'
    CompanyName       = 'Capgemini'
    Copyright         = '(c) Peter Ruiter. MIT.'
    Description       = 'Compare and move Dynamics 365 Contact Center configuration across environments without the Configuration Migration tool.'
    PowerShellVersion = '7.2'
    FunctionsToExport = @(
        'Connect-CcEnvironment',
        'Compare-CcConfig',
        'New-CcPlan',
        'Invoke-CcPlan',
        'Restore-CcRun',
        'New-CcRunRecord',
        'Invoke-CcRunJob',
        'Invoke-CcRollbackJob',
        'New-CcReadCache',
        'Export-CcReadCache',
        'Import-CcReadCache',
        'Test-CcRunStale'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData = @{
        PSData = @{
            Tags       = @('Dynamics365','ContactCenter','ALM','Dataverse','UnifiedRouting')
            LicenseUri = 'https://opensource.org/licenses/MIT'
            ProjectUri = 'https://github.com/peterruiter/d365-contactcenter-alm'
        }
    }
}
