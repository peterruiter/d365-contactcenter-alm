<#
.SYNOPSIS
    Provision and publish the ALM backend Function app.
.DESCRIPTION
    Creates the resource group, storage account, and PowerShell Function app if they are missing,
    sets the app settings the engine needs, copies the manifest into the app, and publishes.

    Prerequisites:
      - Azure CLI (az), signed in: az login
      - Azure Functions Core Tools (func)
      - An Entra app registration for the service principal, added as an Application User in every
        environment (see docs/backend-service-principal.md). Its secret goes in Key Vault or the
        CCALM_CLIENT_SECRET setting.
      - The environments registry JSON (same shape as config/environments.example.json).
.PARAMETER ResourceGroup
    Resource group name.
.PARAMETER FunctionApp
    Globally unique Function app name.
.PARAMETER Location
    Azure region, e.g. westeurope.
.PARAMETER EnvironmentsFile
    Path to the environments registry JSON. Its contents go into the CCALM_ENVIRONMENTS setting.
.EXAMPLE
    ./scripts/deploy-backend.ps1 -ResourceGroup rg-ccalm -FunctionApp ccalm-func-nl -Location westeurope -EnvironmentsFile ./environments.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $ResourceGroup,
    [Parameter(Mandatory)] [string] $FunctionApp,
    [string] $Location = 'westeurope',
    [Parameter(Mandatory)] [string] $EnvironmentsFile
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$appDir = Join-Path $root 'backend/function-app'

foreach ($tool in 'az', 'func') {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "$tool not found. Install it and sign in first."
    }
}
if (-not (Test-Path $EnvironmentsFile)) { throw "Environments file not found: $EnvironmentsFile" }

$storage = ($FunctionApp -replace '[^a-z0-9]', '').ToLower()
if ($storage.Length -gt 22) { $storage = $storage.Substring(0, 22) }
$storage = "st$storage"

Write-Host "Resource group $ResourceGroup" -ForegroundColor Cyan
az group create --name $ResourceGroup --location $Location --only-show-errors | Out-Null

Write-Host "Storage account $storage" -ForegroundColor Cyan
az storage account create --name $storage --resource-group $ResourceGroup --location $Location --sku Standard_LRS --only-show-errors | Out-Null

Write-Host "Function app $FunctionApp (PowerShell 7.4)" -ForegroundColor Cyan
az functionapp create `
    --name $FunctionApp `
    --resource-group $ResourceGroup `
    --storage-account $storage `
    --consumption-plan-location $Location `
    --runtime powershell `
    --runtime-version 7.4 `
    --functions-version 4 `
    --os-type Windows `
    --only-show-errors | Out-Null

# App settings the engine reads. The service principal secret should be a Key Vault reference
# in production; set it here only for a quick start.
$envJson = (Get-Content $EnvironmentsFile -Raw)
$cfg = $envJson | ConvertFrom-Json

Write-Host 'Setting app settings' -ForegroundColor Cyan
az functionapp config appsettings set --name $FunctionApp --resource-group $ResourceGroup --only-show-errors --settings `
    "CCALM_TENANT_ID=$($cfg.tenantId)" `
    "CCALM_CLIENT_ID=$($cfg.clientId)" `
    "CCALM_ENVIRONMENTS=$envJson" `
    "CCALM_RUNS_CONTAINER=ccalm-runs" | Out-Null

Write-Warning "Set the service principal secret out of band, ideally a Key Vault reference:"
Write-Host "  az functionapp config appsettings set --name $FunctionApp --resource-group $ResourceGroup --settings CCALM_CLIENT_SECRET='@Microsoft.KeyVault(SecretUri=...)'" -ForegroundColor DarkGray

# Ship the manifest inside the app so the engine resolves it locally.
Copy-Item (Join-Path $root 'config/manifest.json') (Join-Path $appDir 'manifest.json') -Force

Write-Host 'Publishing' -ForegroundColor Cyan
Push-Location $appDir
try {
    func azure functionapp publish $FunctionApp --powershell
}
finally {
    Pop-Location
}

Write-Host ''
Write-Host "Published. Base URL: https://$FunctionApp.azurewebsites.net/api" -ForegroundColor Green
Write-Host 'Next:' -ForegroundColor Yellow
Write-Host '  1. Enable App Service Authentication (Easy Auth) with Entra ID on the Function app.' -ForegroundColor DarkGray
Write-Host '  2. Create the custom connector from ./connector, pointing host at this Function.' -ForegroundColor DarkGray
Write-Host '  3. In the code app: pac code add-data-source for that connector, then set VITE_ALM_SOURCE=backend.' -ForegroundColor DarkGray
