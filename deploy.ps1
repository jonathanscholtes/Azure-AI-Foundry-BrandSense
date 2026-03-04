# BrandSense - Main Deployment Orchestrator
# This script coordinates the full end-to-end deployment

param (
    [Parameter(Mandatory=$false)]
    [ValidateSet("init", "validate", "plan", "apply", "all", "destroy", "output", "fmt", "clean")]
    [string]$Action = "all",

    [Parameter(Mandatory=$true)]
    [string]$Subscription,

    [Parameter(Mandatory=$false)]
    [string]$Location = "eastus2",

    [Parameter(Mandatory=$false)]
    [string]$Environment = "dev",

    # Terraform remote state — storage account must be globally unique.
    # The resource group rg-tfstate-brnd is created automatically.
    [Parameter(Mandatory=$false)]
    [string]$TfStateStorageAccount = "stotfstatebrnd",

    [Parameter(Mandatory=$false)]
    [string]$TfStateResourceGroup = "rg-tfstate-brnd",

    # Run New-GitHubOidc.ps1 to create/update the Entra app registration and
    # set the 3 GitHub Actions secrets automatically. Requires 'gh' CLI.
    [Parameter(Mandatory=$false)]
    [switch]$SetupGitHub
)

Set-StrictMode -Version Latest
Set-Variable -Name ErrorActionPreference -Value 'Stop'

# Import common functions
Import-Module "$PSScriptRoot\scripts\common\DeploymentFunctions.psm1" -Force

Write-Host @"

============================================================
  BrandSense - Deployment Orchestrator
============================================================

"@ -ForegroundColor Cyan

# Initialize Azure context
Initialize-AzureContext -Subscription $Subscription

# ---------------------------------------------------------------------------
# PHASE 0: Bootstrap Terraform remote state backend
# (idempotent — safe to run every deploy)
# ---------------------------------------------------------------------------
Write-Host "`n=== PHASE 0: Terraform State Backend Bootstrap ===" -ForegroundColor Magenta

Write-Host "  Resource group : $TfStateResourceGroup" -ForegroundColor Cyan
Write-Host "  Storage account: $TfStateStorageAccount" -ForegroundColor Cyan

az group create `
    --name $TfStateResourceGroup `
    --location $Location `
    --output none

az storage account create `
    --name $TfStateStorageAccount `
    --resource-group $TfStateResourceGroup `
    --sku Standard_LRS `
    --allow-blob-public-access false `
    --min-tls-version TLS1_2 `
    --output none

az storage container create `
    --name tfstate `
    --account-name $TfStateStorageAccount `
    --auth-mode login `
    --output none

Write-Host "State backend ready." -ForegroundColor Green

# ---------------------------------------------------------------------------
# PHASE 1: Deploy Infrastructure (Terraform)
# ---------------------------------------------------------------------------
Write-Host "`n=== PHASE 1: Infrastructure Deployment ===" -ForegroundColor Magenta

& "$PSScriptRoot\scripts\Deploy-Infrastructure.ps1" `
    -Action $Action `
    -Subscription $Subscription `
    -Location $Location `
    -Environment $Environment `
    -TfStateStorageAccount $TfStateStorageAccount

if ($LASTEXITCODE -ne 0) {
    Write-Host "Infrastructure deployment failed" -ForegroundColor Red
    exit 1
}

# Skip remaining phases for non-deployment actions
if ($Action -in @("output", "fmt", "clean", "validate", "plan", "init")) {
    exit 0
}

# ---------------------------------------------------------------------------
# Read Terraform outputs — used by all subsequent phases
# ---------------------------------------------------------------------------
Write-Host "`nReading Terraform outputs..." -ForegroundColor Cyan

$infraDir = Join-Path $PSScriptRoot "infra"
Push-Location $infraDir

try {
    $tfOutputsJson = terraform output -json 2>$null
    $tfOutputs     = $tfOutputsJson | ConvertFrom-Json
} catch {
    Write-Host "WARNING: Could not read Terraform outputs — Phases 1.5–4 may be skipped." -ForegroundColor Yellow
    $tfOutputs = $null
}

Pop-Location

$resourceGroupName   = if ($tfOutputs) { $tfOutputs.resource_group_name.value }         else { $null }
$keyVaultName        = if ($tfOutputs) { $tfOutputs.key_vault_name.value }               else { $null }
$searchEndpoint      = if ($tfOutputs) { $tfOutputs.search_service_endpoint.value }      else { $null }
$aiAccountName       = if ($tfOutputs) { $tfOutputs.ai_account_name.value }              else { $null }
$aiProjectName       = if ($tfOutputs) { $tfOutputs.ai_project_name.value }              else { $null }
$containerAppUrl     = if ($tfOutputs -and $tfOutputs.PSObject.Properties["container_app_url"]) {
                           $tfOutputs.container_app_url.value
                       } else { "<container-app-url>" }

# Derive Foundry project endpoint from account + project name
$aiProjectEndpoint = $null
if ($aiAccountName -and $aiProjectName) {
    $aiProjectEndpoint = "https://$aiAccountName.services.ai.azure.com/api/projects/$aiProjectName"
}

if ($resourceGroupName)  { Write-Host "  Resource Group      : $resourceGroupName"  -ForegroundColor Gray }
if ($keyVaultName)       { Write-Host "  Key Vault           : $keyVaultName"        -ForegroundColor Gray }
if ($searchEndpoint)     { Write-Host "  Search Endpoint     : $searchEndpoint"      -ForegroundColor Gray }
if ($aiProjectEndpoint)  { Write-Host "  AI Project Endpoint : $aiProjectEndpoint"   -ForegroundColor Gray }
if ($containerAppUrl -ne "<container-app-url>") {
    Write-Host "  Container App URL   : $containerAppUrl" -ForegroundColor Gray
}

# ---------------------------------------------------------------------------
# PHASE 1.5: Build & push container images to ACR
# ACR is created by Terraform in Phase 1, so this must run after apply.
# ---------------------------------------------------------------------------
Write-Host "`n=== PHASE 1.5: Build & Push Container Images ===" -ForegroundColor Magenta

$acrName = if ($tfOutputs -and $tfOutputs.PSObject.Properties["container_registry_login_server"]) {
               # login_server is e.g. acrbrndabc12345.azurecr.io — strip the domain suffix
               ($tfOutputs.container_registry_login_server.value -split '\.')[0]
           } else { $null }

if (-not $acrName -or -not $resourceGroupName) {
    Write-Host "WARNING: ACR name or resource group not available from Terraform outputs — skipping image build." -ForegroundColor Yellow
    Write-Host "         Build manually: .\scripts\Deploy-Containers.ps1 -ContainerRegistryName <name> -ResourceGroupName <rg>" -ForegroundColor Gray
} else {
    & "$PSScriptRoot\scripts\Deploy-Containers.ps1" `
        -ContainerRegistryName $acrName `
        -ResourceGroupName     $resourceGroupName

    if ($LASTEXITCODE -ne 0) {
        Write-Host "Container image build failed" -ForegroundColor Red
        exit 1
    }
}

# ---------------------------------------------------------------------------
# PHASE 2: APIM Configuration (resource provisioning only)
# NOTE: APIM MCP Server is a manual portal step after this phase.
# ---------------------------------------------------------------------------
Write-Host "`n=== PHASE 2: APIM Configuration (resource provisioning only) ===" -ForegroundColor Magenta

& "$PSScriptRoot\scripts\Deploy-APIM-Configuration.ps1" `
    -Subscription $Subscription `
    -Environment $Environment

if ($LASTEXITCODE -ne 0) {
    Write-Host "APIM configuration failed" -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------------------
# PHASE 2.5: Register AI Search connection in the Foundry project
# Uses 'az ml connection create' (requires: az extension add --name ml)
# Creates the 'brandsense-search' connection with keyless (managed identity) auth.
# Idempotent — 'az ml connection create' updates if the connection already exists.
# ---------------------------------------------------------------------------
Write-Host "`n=== PHASE 2.5: Register AI Search Connection in Foundry ===" -ForegroundColor Magenta

$resourceGroupName = if ($tfOutputs) { $tfOutputs.resource_group_name.value } else { $null }

if (-not $searchEndpoint -or -not $resourceGroupName -or -not $aiProjectName) {
    Write-Host "WARNING: Missing search endpoint or project details — skipping connection registration." -ForegroundColor Yellow
    Write-Host "         The agent deploy step will attempt auto-discover of any existing AI Search connection." -ForegroundColor Gray
} else {
    # Ensure the ml extension is available
    $mlExt = az extension show --name ml 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Installing 'az ml' extension..." -ForegroundColor Yellow
        az extension add --name ml --yes
    }

    # Write connection YAML to a temp file
    $connectionYaml = @"
name: brandsense-search
type: azure_ai_search
endpoint: $searchEndpoint
"@
    $tmpYaml = [System.IO.Path]::GetTempFileName() + ".yml"
    Set-Content -Path $tmpYaml -Value $connectionYaml -Encoding UTF8

    Write-Host "Registering AI Search connection 'brandsense-search' in project '$aiProjectName'..." -ForegroundColor Yellow
    az ml connection create `
        --file $tmpYaml `
        --resource-group $resourceGroupName `
        --workspace-name $aiProjectName

    Remove-Item $tmpYaml -Force -ErrorAction SilentlyContinue

    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] AI Search connection 'brandsense-search' registered." -ForegroundColor Green
    } else {
        Write-Host "WARNING: Connection registration failed — agent deploy will attempt auto-discover." -ForegroundColor Yellow
    }
}

# ---------------------------------------------------------------------------
# PHASE 3: Seed AI Search guidelines index
# ---------------------------------------------------------------------------
Write-Host "`n=== PHASE 3: Seed Guidelines Index ===" -ForegroundColor Magenta

if (-not $searchEndpoint) {
    Write-Host "WARNING: search_service_endpoint not available from Terraform outputs — skipping." -ForegroundColor Yellow
} else {
    # Check Python
    try {
        $pyVer = python --version 2>&1
        Write-Host "Python found: $pyVer" -ForegroundColor Green
    } catch {
        Write-Host "WARNING: Python not found — skipping guidelines seeding." -ForegroundColor Yellow
        $searchEndpoint = $null
    }

    if ($searchEndpoint) {
        Write-Host "Installing guidelines dependencies..." -ForegroundColor Yellow
        pip install -r "$PSScriptRoot\scripts\load\requirements.txt" --quiet
        if ($LASTEXITCODE -ne 0) { throw "pip install (guidelines) failed." }

        Write-Host "Seeding brandsense-guidelines index..." -ForegroundColor Yellow
        $env:AZURE_SEARCH_ENDPOINT = $searchEndpoint
        python "$PSScriptRoot\scripts\load\guidelines.py"

        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] Guidelines index seeded." -ForegroundColor Green
        } else {
            Write-Host "WARNING: Guidelines seeding failed (exit $LASTEXITCODE) — continuing." -ForegroundColor Yellow
        }
    }
}

# ---------------------------------------------------------------------------
# PHASE 4: Deploy Foundry Agents
# ---------------------------------------------------------------------------
Write-Host "`n=== PHASE 4: Deploy Foundry Agents ===" -ForegroundColor Magenta

if (-not $aiProjectEndpoint -or -not $keyVaultName) {
    Write-Host "WARNING: AI project endpoint or Key Vault name not available — skipping agent deployment." -ForegroundColor Yellow
    Write-Host "         Run manually: .\scripts\Deploy-FoundryAgents.ps1 -AiProjectEndpoint <url> -KeyVaultName <name>" -ForegroundColor Gray
} else {
    & "$PSScriptRoot\scripts\Deploy-FoundryAgents.ps1" `
        -AiProjectEndpoint  $aiProjectEndpoint `
        -KeyVaultName       $keyVaultName `
        -SearchConnectionName "brandsense-search"

    if ($LASTEXITCODE -ne 0) {
        Write-Host "WARNING: Agent deployment failed (exit $LASTEXITCODE) — continuing." -ForegroundColor Yellow
    } else {
        Write-Host "[OK] Foundry agents deployed." -ForegroundColor Green
    }
}

# ---------------------------------------------------------------------------
# PHASE 5: Configure GitHub Actions OIDC secrets (optional, -SetupGitHub)
# ---------------------------------------------------------------------------
$githubOidcConfigured = $false

if ($SetupGitHub) {
    Write-Host "`n=== PHASE 5: GitHub Actions OIDC Setup ===" -ForegroundColor Magenta

    # Verify gh CLI is available
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Write-Host "WARNING: 'gh' CLI not found — skipping GitHub secret setup." -ForegroundColor Yellow
        Write-Host "         Install from https://cli.github.com then re-run with -SetupGitHub" -ForegroundColor Gray
    } else {
        & "$PSScriptRoot\scripts\New-GitHubOidc.ps1"

        if ($LASTEXITCODE -eq 0) {
            $githubOidcConfigured = $true
            Write-Host "[OK] GitHub OIDC configured — secrets written to repo." -ForegroundColor Green
        } else {
            Write-Host "WARNING: GitHub OIDC setup failed (exit $LASTEXITCODE) — continuing." -ForegroundColor Yellow
        }
    }
}

# ---------------------------------------------------------------------------
# Deployment Summary
# ---------------------------------------------------------------------------
Write-Host @"

============================================================
                 Deployment Summary
============================================================

"@ -ForegroundColor Cyan

Write-Host "[OK] Azure Infrastructure deployed (AI Foundry, AI Search, APIM, Container Apps, Key Vault)" -ForegroundColor Green
Write-Host "[OK] Terraform configuration applied" -ForegroundColor Green
Write-Host "[OK] Guidelines index seeded (brandsense-guidelines)" -ForegroundColor Green
Write-Host "[OK] APIM instance provisioned" -ForegroundColor Green

if ($aiProjectEndpoint -and $keyVaultName) {
    Write-Host "[OK] Foundry agents deployed (researcher / auditor / briefer)" -ForegroundColor Green
}

Write-Host ""
Write-Host "[!!] ACTION REQUIRED: Manually configure APIM MCP Server in the portal" -ForegroundColor Yellow
Write-Host "       APIM → APIs → MCP Servers → Create → Expose an API as an MCP server" -ForegroundColor Yellow
Write-Host "       Import OpenAPI spec from: https://$containerAppUrl/openapi.json" -ForegroundColor Yellow
Write-Host ""
Write-Host "[!!] ACTION REQUIRED: Add the APIM MCP endpoint to brandsense-auditor in Foundry" -ForegroundColor Yellow
Write-Host "       Foundry → Agents → brandsense-auditor → Tools → Add tool (MCP)" -ForegroundColor Yellow

Write-Host "`n=== Next Steps ===" -ForegroundColor Cyan

Write-Host "* Get the APIM MCP endpoint after manual portal setup:" -ForegroundColor Gray
Write-Host "* Verify agents in Foundry portal → Agents (researcher / auditor / briefer)" -ForegroundColor Gray

Write-Host "`n=== GitHub Actions Secrets ===" -ForegroundColor Cyan
if ($githubOidcConfigured) {
    Write-Host "  [OK] OIDC configured — AZURE_CLIENT_ID / TENANT_ID / SUBSCRIPTION_ID written to repo." -ForegroundColor Green
} else {
    Write-Host "  Not configured. Re-run with -SetupGitHub to do this automatically, or run manually:" -ForegroundColor Yellow
    Write-Host "    .\scripts\New-GitHubOidc.ps1" -ForegroundColor White
    Write-Host "  Requires: az login + gh auth login" -ForegroundColor Gray
}


Write-Host "`n=== Service Endpoints ===" -ForegroundColor Cyan

if ($containerAppUrl -and $containerAppUrl -ne "<container-app-url>") {
    Write-Host "  API : $containerAppUrl/docs"   -ForegroundColor Green
    Write-Host "  UI  : $containerAppUrl"         -ForegroundColor Cyan
} else {
    Write-Host "  Endpoints not yet available — run: terraform output container_app_url" -ForegroundColor Yellow
}
Write-Host @"

============================================================
      BrandSense Deployment Complete!
============================================================

"@ -ForegroundColor Green
