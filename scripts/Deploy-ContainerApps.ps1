# Deploy Container Apps
# This script deploys container apps using the bicep template
# It redeploys only the container apps module after images have been pushed to ACR

param (
    # Pass the object returned by Deploy-Infrastructure.ps1 to populate all infra params automatically.
    # Alternatively, supply each infra param individually for manual/standalone invocation.
    [Parameter(Mandatory=$false)]
    [PSCustomObject]$InfraOutputs,

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
    [string]$ServiceBusNamespaceName,

    [Parameter(Mandatory=$false)]
    [string]$ResourceToken,

    [Parameter(Mandatory=$false)]
    [string]$ManagedIdentityName,

    [Parameter(Mandatory=$false)]
    [string]$ManagedIdentityClientId = '',

    [Parameter(Mandatory=$false)]
    [string]$LogAnalyticsWorkspaceName,

    [Parameter(Mandatory=$false)]
    [string]$AzureMonitorIngestionEndpoint = '',

    [Parameter(Mandatory=$false)]
    [string]$CosmosEndpoint,

    [Parameter(Mandatory=$false)]
    [string]$CosmosDbDatabaseName = 'fleetmind',

    [Parameter(Mandatory=$false)]
    [string]$KeyVaultName = '',

    [Parameter(Mandatory=$false)]
    [string]$ApplicationInsightsName = '',

    [Parameter(Mandatory=$false)]
    [string]$TeamsWebhookUrl = '',

    # Agent container parameters
    [Parameter(Mandatory=$false)]
    [string]$AiProjectEndpoint = '',

    [Parameter(Mandatory=$false)]
    [string]$ModelDeployment = 'gpt-4.1',

    # ApimSubscriptionKey removed — key is now retrieved from APIM via listSecrets() in apim.bicep

    [Parameter(Mandatory=$false)]
    [string]$ApplicationInsightsConnectionString = '',

    [Parameter(Mandatory=$false)]
    [int]$AgentMaxConcurrentEvents = 10
)

# When InfraOutputs is supplied, use it to fill any params not explicitly provided
if ($InfraOutputs) {
    if (-not $ResourceGroupName)             { $ResourceGroupName             = $InfraOutputs.resourceGroupName }
    if (-not $ContainerRegistryName)         { $ContainerRegistryName         = $InfraOutputs.containerRegistryName }
    if (-not $ServiceBusNamespaceName)       { $ServiceBusNamespaceName       = $InfraOutputs.serviceBusNamespaceName }
    if (-not $ResourceToken)                 { $ResourceToken                 = $InfraOutputs.ResourceToken }
    if (-not $ManagedIdentityName)           { $ManagedIdentityName           = $InfraOutputs.managedIdentityName }
    if (-not $ManagedIdentityClientId)       { $ManagedIdentityClientId       = $InfraOutputs.managedIdentityClientId }
    if (-not $LogAnalyticsWorkspaceName)     { $LogAnalyticsWorkspaceName     = $InfraOutputs.logAnalyticsWorkspaceName }
    if (-not $AzureMonitorIngestionEndpoint) { $AzureMonitorIngestionEndpoint = $InfraOutputs.prometheusIngestionEndpoint }
    if (-not $CosmosEndpoint)                { $CosmosEndpoint                = $InfraOutputs.cosmosDbEndpoint }
    if ($InfraOutputs.cosmosDbDatabaseName -and $CosmosDbDatabaseName -eq 'fleetmind') {
        $CosmosDbDatabaseName = $InfraOutputs.cosmosDbDatabaseName
    }
    if (-not $KeyVaultName -and $InfraOutputs.keyVaultName) { $KeyVaultName = $InfraOutputs.keyVaultName }
    if (-not $ApplicationInsightsName -and $InfraOutputs.applicationInsightsName) { $ApplicationInsightsName = $InfraOutputs.applicationInsightsName }
    if (-not $AiProjectEndpoint -and $InfraOutputs.aiProjectEndpoint)             { $AiProjectEndpoint = $InfraOutputs.aiProjectEndpoint }
}

Set-StrictMode -Version Latest
Set-Variable -Name ErrorActionPreference -Value 'Stop'

Write-Host "`n=== Deploying Container Apps ===" -ForegroundColor Cyan
Write-Host "Resource Group: $ResourceGroupName" -ForegroundColor White
Write-Host "Container Registry: $ContainerRegistryName" -ForegroundColor White

# Deploy Bicep template
$deploymentNameApps = "deployment-$ProjectName-app-$ResourceToken"
$appsTemplateFile = "infra/app/main.bicep"

$deploymentOutputApps = az deployment sub create `
    --name $deploymentNameApps `
    --location $Location `
    --template-file $appsTemplateFile `
    --parameters `
        environmentName=$EnvironmentName `
        projectName=$ProjectName `
        location=$Location `
        resourceGroupName=$ResourceGroupName `
        resourceToken=$ResourceToken `
        managedIdentityName=$ManagedIdentityName `
        logAnalyticsWorkspaceName=$LogAnalyticsWorkspaceName `
        containerRegistryName=$ContainerRegistryName `
        serviceBusNamespaceName=$ServiceBusNamespaceName `
        azureMonitorIngestionEndpoint=$AzureMonitorIngestionEndpoint `
        managedIdentityClientId=$ManagedIdentityClientId `
        cosmosEndpoint=$CosmosEndpoint `
        cosmosDatabaseName=$CosmosDbDatabaseName `
        keyVaultName=$KeyVaultName `
        applicationInsightsName=$ApplicationInsightsName `
        teamsWebhookUrl=$TeamsWebhookUrl `
        aiProjectEndpoint=$AiProjectEndpoint `
        modelDeployment=$ModelDeployment `
        applicationInsightsConnectionString=$ApplicationInsightsConnectionString `
        agentMaxConcurrentEvents=$AgentMaxConcurrentEvents `
    --query "properties.outputs" 

if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to deploy container apps module" -ForegroundColor Red
    Write-Host $deploymentOutputApps -ForegroundColor Red
    throw "Container apps deployment failed"
}

$outputs = $deploymentOutputApps | ConvertFrom-Json

Write-Host "`n[OK] Container apps deployed successfully" -ForegroundColor Green

if ($outputs.containerAppEnvironmentName) {
    Write-Host "Container App Environment: $($outputs.containerAppEnvironmentName.value)" -ForegroundColor White
}
if ($outputs.stateApiContainerAppFqdn) {
    Write-Host "State API FQDN:            $($outputs.stateApiContainerAppFqdn.value)" -ForegroundColor White
}
if ($outputs.telemetryApiContainerAppFqdn) {
    Write-Host "Telemetry API FQDN:        $($outputs.telemetryApiContainerAppFqdn.value)" -ForegroundColor White
}
if ($outputs.routingApiContainerAppFqdn) {
    Write-Host "Routing API FQDN:          $($outputs.routingApiContainerAppFqdn.value)" -ForegroundColor White
}
if ($outputs.maintenanceApiContainerAppFqdn) {
    Write-Host "Maintenance API FQDN:      $($outputs.maintenanceApiContainerAppFqdn.value)" -ForegroundColor White
}
if ($outputs.complianceApiContainerAppFqdn) {
    Write-Host "Compliance API FQDN:       $($outputs.complianceApiContainerAppFqdn.value)" -ForegroundColor White
}
if ($outputs.alertsApiContainerAppFqdn) {
    Write-Host "Alerts API FQDN:           $($outputs.alertsApiContainerAppFqdn.value)" -ForegroundColor White
}
if ($outputs.apimGatewayUrl) {
    Write-Host "APIM Gateway URL:          $($outputs.apimGatewayUrl.value)" -ForegroundColor Cyan
}
if ($outputs.stateMcpUrl) {
    Write-Host "`nMCP Server Endpoints:" -ForegroundColor Cyan
    Write-Host "  State MCP:       $($outputs.stateMcpUrl.value)" -ForegroundColor White
    Write-Host "  Telemetry MCP:   $($outputs.telemetryMcpUrl.value)" -ForegroundColor White
    Write-Host "  Routing MCP:     $($outputs.routingMcpUrl.value)" -ForegroundColor White
    Write-Host "  Maintenance MCP: $($outputs.maintenanceMcpUrl.value)" -ForegroundColor White
    Write-Host "  Compliance MCP:  $($outputs.complianceMcpUrl.value)" -ForegroundColor White
    Write-Host "  Alerts MCP:      $($outputs.alertsMcpUrl.value)" -ForegroundColor White
}

if ($outputs.agentContainerAppName -and $outputs.agentContainerAppName.value) {
    Write-Host "Agent Container App:       $($outputs.agentContainerAppName.value)" -ForegroundColor Cyan
}

Write-Host "`n  Note: UI container will be built and deployed separately once API FQDNs are known." -ForegroundColor DarkGray

# Wire routing-api URL into the simulator so trucks follow road-snapped waypoints.
# routing-api uses internal ingress so it is only reachable from within the Container App Environment.
if ($outputs.routingApiContainerAppFqdn -and $outputs.routingApiContainerAppFqdn.value) {
    $routingFqdn = $outputs.routingApiContainerAppFqdn.value
    $routingUrl  = "https://$routingFqdn"
    $simulatorAppName = "ca-simulator-$ResourceToken"

    Write-Host "`n=== Wiring ROUTING_API_URL into simulator ===" -ForegroundColor Cyan
    Write-Host "Routing URL: $routingUrl" -ForegroundColor White

    az containerapp update `
        --name $simulatorAppName `
        --resource-group $ResourceGroupName `
        --container-name fleet-simulator `
        --set-env-vars "ROUTING_API_URL=$routingUrl" | Out-Null

    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] ROUTING_API_URL set on $simulatorAppName" -ForegroundColor Green
    } else {
        Write-Host "[WARN] Failed to set ROUTING_API_URL on simulator - set it manually or redeploy" -ForegroundColor Yellow
    }
}

# Return outputs as object
return [PSCustomObject]@{
    containerAppEnvironmentName    = $outputs.containerAppEnvironmentName.value
    stateApiContainerAppFqdn       = $outputs.stateApiContainerAppFqdn.value
    telemetryApiContainerAppFqdn   = $outputs.telemetryApiContainerAppFqdn.value
    routingApiContainerAppFqdn     = $outputs.routingApiContainerAppFqdn.value
    maintenanceApiContainerAppFqdn = $outputs.maintenanceApiContainerAppFqdn.value
    complianceApiContainerAppFqdn  = $outputs.complianceApiContainerAppFqdn.value
    alertsApiContainerAppFqdn      = $outputs.alertsApiContainerAppFqdn.value
    apimGatewayUrl                 = if ($outputs.apimGatewayUrl) { $outputs.apimGatewayUrl.value } else { '' }
    stateMcpUrl                     = if ($outputs.stateMcpUrl) { $outputs.stateMcpUrl.value } else { '' }
    telemetryMcpUrl                 = if ($outputs.telemetryMcpUrl) { $outputs.telemetryMcpUrl.value } else { '' }
    routingMcpUrl                   = if ($outputs.routingMcpUrl) { $outputs.routingMcpUrl.value } else { '' }
    maintenanceMcpUrl               = if ($outputs.maintenanceMcpUrl) { $outputs.maintenanceMcpUrl.value } else { '' }
    complianceMcpUrl                = if ($outputs.complianceMcpUrl) { $outputs.complianceMcpUrl.value } else { '' }
    alertsMcpUrl                    = if ($outputs.alertsMcpUrl) { $outputs.alertsMcpUrl.value } else { '' }
    apimName                       = if ($outputs.apimName) { $outputs.apimName.value } else { '' }
    agentContainerAppName          = if ($outputs.agentContainerAppName) { $outputs.agentContainerAppName.value } else { '' }
}
