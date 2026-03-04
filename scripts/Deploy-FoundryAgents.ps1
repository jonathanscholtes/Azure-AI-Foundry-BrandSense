<#
.SYNOPSIS
    Deploy BrandSense Foundry agents.

.DESCRIPTION
    Wraps the Python agent provisioning script (scripts/deploy_foundry_agents.py).
    Creates or updates the three BrandSense agents in the Foundry project and
    writes their IDs to Key Vault.

.PARAMETER AiProjectEndpoint
    Azure AI Foundry project endpoint.
    e.g. https://<account>.services.ai.azure.com/api/projects/<project>

.PARAMETER KeyVaultName
    Name of the Azure Key Vault where agent IDs are stored.

.PARAMETER ModelDeployment
    Foundry model deployment name. Defaults to gpt-4.1

.PARAMETER SearchConnectionName
    Name of the Azure AI Search connection registered in the Foundry project
    (created by deploy.ps1 Phase 2.5 via 'az ml connection create').
    Defaults to 'brandsense-search'. The Python script resolves this name
    to a resource ID via the SDK; if not found it auto-discovers the first
    AI Search connection in the project.

.EXAMPLE
    .\scripts\Deploy-FoundryAgents.ps1 `
        -AiProjectEndpoint "https://myaccount.services.ai.azure.com/api/projects/myproject" `
        -KeyVaultName      "kv-brandsense-prod"
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$AiProjectEndpoint,

    [Parameter(Mandatory = $true)]
    [string]$KeyVaultName,

    [Parameter(Mandatory = $false)]
    [string]$ModelDeployment = "gpt-4.1",

    [Parameter(Mandatory = $false)]
    [string]$SearchConnectionName = "brandsense-search"
)

$ErrorActionPreference = "Stop"

Write-Host "`n=== BrandSense: Deploy Foundry Agents ===" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# 1. Check Python
# ---------------------------------------------------------------------------
try {
    $pythonVersion = python --version 2>&1
    Write-Host "Python found: $pythonVersion" -ForegroundColor Green
} catch {
    Write-Host "Python not found — cannot deploy agents." -ForegroundColor Red
    throw "Python is required for agent deployment."
}

# ---------------------------------------------------------------------------
# 2. Install Python dependencies
# ---------------------------------------------------------------------------
Write-Host "`nInstalling Python dependencies..." -ForegroundColor Yellow
pip install -r "$PSScriptRoot\requirements-agents.txt" --quiet
if ($LASTEXITCODE -ne 0) { throw "pip install failed." }

# ---------------------------------------------------------------------------
# 3. Print configuration
# ---------------------------------------------------------------------------
Write-Host "`nAgent Configuration:" -ForegroundColor Cyan
Write-Host "  Project Endpoint   : $AiProjectEndpoint"     -ForegroundColor White
Write-Host "  Model Deployment   : $ModelDeployment"       -ForegroundColor White
Write-Host "  Key Vault Name     : $KeyVaultName"          -ForegroundColor White
Write-Host "  Search Connection  : $SearchConnectionName"  -ForegroundColor White


# ---------------------------------------------------------------------------
# 4. Run the Python provisioning script
# ---------------------------------------------------------------------------
Write-Host "`nProvisioning agents in Microsoft Foundry..." -ForegroundColor Yellow

$pythonArgs = @(
    "$PSScriptRoot\deploy_foundry_agents.py",
    "--project-endpoint", $AiProjectEndpoint,
    "--model-deployment", $ModelDeployment,
    "--key-vault-name",   $KeyVaultName,
    "--search-connection-name", $SearchConnectionName
)

python @pythonArgs

if ($LASTEXITCODE -ne 0) {
    throw "Agent deployment script failed (exit code $LASTEXITCODE)."
}

Write-Host "`n[OK] Foundry agents deployed and IDs written to Key Vault." -ForegroundColor Green
Write-Host "`n=== Done ===" -ForegroundColor Cyan
