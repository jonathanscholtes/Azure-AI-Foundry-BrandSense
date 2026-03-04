# Deploy-ContainerUI.ps1
# Builds the fleet-ui container image with real service API FQDNs baked into the Vite
# bundle, then deploys the UI Container App using infra/app/ui-main.bicep.
#
# This script is intentionally called AFTER Deploy-ContainerApps.ps1 so the backend
# service FQDNs are known at image build time.

param (
    # Pass the object returned by Deploy-Infrastructure.ps1 to auto-populate infra params.
    [Parameter(Mandatory=$false)]
    [PSCustomObject]$InfraOutputs,

    # Pass the object returned by Deploy-ContainerApps.ps1 to auto-populate service FQDNs.
    [Parameter(Mandatory=$false)]
    [PSCustomObject]$ContainerAppsOutputs,

    [Parameter(Mandatory=$true)]
    [string]$ProjectName,

    [Parameter(Mandatory=$true)]
    [string]$EnvironmentName,

    [Parameter(Mandatory=$true)]
    [string]$Location,

    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory=$false)]
    [string]$ContainerRegistryName,

    [Parameter(Mandatory=$false)]
    [string]$ResourceToken,

    [Parameter(Mandatory=$false)]
    [string]$ManagedIdentityName,

    [Parameter(Mandatory=$false)]
    [string]$ContainerAppEnvironmentName,

    [Parameter(Mandatory=$false)]
    [string]$AzureMapsKey = ''
)

# ── Resolve params from upstream outputs ──────────────────────────────────────

if ($InfraOutputs) {
    if (-not $ResourceGroupName)           { $ResourceGroupName           = $InfraOutputs.resourceGroupName }
    if (-not $ContainerRegistryName)       { $ContainerRegistryName       = $InfraOutputs.containerRegistryName }
    if (-not $ResourceToken)               { $ResourceToken               = $InfraOutputs.ResourceToken }
    if (-not $ManagedIdentityName)         { $ManagedIdentityName         = $InfraOutputs.managedIdentityName }
}

# Auto-fetch Azure Maps key from Key Vault if not supplied by the caller
if (-not $AzureMapsKey) {
    $kvName = if ($InfraOutputs -and $InfraOutputs.keyVaultName) { $InfraOutputs.keyVaultName } else { $null }
    if ($kvName) {
        Write-Host "Fetching azure-maps-key from Key Vault '$kvName'..." -ForegroundColor DarkGray
        $AzureMapsKey = (az keyvault secret show --vault-name $kvName --name 'azure-maps-key' --query 'value' -o tsv 2>$null)
        if (-not $AzureMapsKey) { Write-Warning "Could not retrieve azure-maps-key from Key Vault. Map tiles will not load." }
    }
}

$StateApiFqdn = ''
if ($ContainerAppsOutputs) {
    if (-not $ContainerAppEnvironmentName) { $ContainerAppEnvironmentName = $ContainerAppsOutputs.containerAppEnvironmentName }
    $StateApiFqdn = $ContainerAppsOutputs.stateApiContainerAppFqdn
}

Set-StrictMode -Version Latest
Set-Variable -Name ErrorActionPreference -Value 'Stop'

Write-Host "`n=== Deploying UI Container ===" -ForegroundColor Cyan
Write-Host "Resource Group:              $ResourceGroupName" -ForegroundColor White
Write-Host "Container Registry:          $ContainerRegistryName" -ForegroundColor White
Write-Host "Container App Environment:   $ContainerAppEnvironmentName" -ForegroundColor White
Write-Host "State API FQDN:              $StateApiFqdn" -ForegroundColor White

# ── 1. Build fleet-ui image with real API URLs baked in ───────────────────────

$WsUrl = if ($StateApiFqdn) { "wss://$StateApiFqdn/ws/fleet" } else { '' }

Write-Host "`nBuilding fleet-ui image with baked-in API URLs..." -ForegroundColor Yellow
Write-Host "  VITE_WS_URL        = $WsUrl" -ForegroundColor DarkGray

& "$PSScriptRoot\Deploy-Containers.ps1" `
    -ContainerRegistryName $ContainerRegistryName `
    -ResourceGroupName $ResourceGroupName `
    -AzureMapsKey $AzureMapsKey `
    -WsUrl $WsUrl `
    -Images @('fleet-ui')

if ($LASTEXITCODE -ne 0) { throw "fleet-ui image build failed." }

# ── 2. Deploy UI Container App via ui-main.bicep ──────────────────────────────

$deploymentName  = "deployment-$ProjectName-ui-$ResourceToken"
$uiTemplateFile  = "infra/app/ui-main.bicep"

Write-Host "`nDeploying UI Container App (infra/app/ui-main.bicep)..." -ForegroundColor Yellow

$deploymentOutput = az deployment sub create `
    --name $deploymentName `
    --location $Location `
    --template-file $uiTemplateFile `
    --parameters `
        environmentName=$EnvironmentName `
        projectName=$ProjectName `
        location=$Location `
        resourceGroupName=$ResourceGroupName `
        resourceToken=$ResourceToken `
        containerAppEnvironmentName=$ContainerAppEnvironmentName `
        managedIdentityName=$ManagedIdentityName `
        containerRegistryName=$ContainerRegistryName `
        stateApiFqdn=$StateApiFqdn `
        wsUrl=$WsUrl `
    --query "properties.outputs"

if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to deploy UI Container App." -ForegroundColor Red
    Write-Host $deploymentOutput -ForegroundColor Red
    throw "UI container app deployment failed."
}

$outputs = $deploymentOutput | ConvertFrom-Json

Write-Host "`n[OK] UI Container App deployed successfully" -ForegroundColor Green

if ($outputs.uiContainerAppFqdn) {
    Write-Host "Dashboard UI URL: https://$($outputs.uiContainerAppFqdn.value)" -ForegroundColor Cyan
}

return [PSCustomObject]@{
    uiContainerAppName = $outputs.uiContainerAppName.value
    uiContainerAppFqdn = $outputs.uiContainerAppFqdn.value
}
