# BrandSense - Main Deployment Orchestrator
# This script coordinates the full end-to-end deployment

param (
       [Parameter(Mandatory=$true)]
    [string]$Subscription,

    [Parameter(Mandatory=$false)]
    [string]$Location = "eastus2",

    [Parameter(Mandatory=$false)]
    [string]$Environment = "dev",

     # Destroy all deployed resources (runs terraform destroy).
    # When omitted the full deployment pipeline runs (equivalent to terraform apply).
    [Parameter(Mandatory=$false)]
    [switch]$Destroy,

    # Terraform remote state — storage account must be globally unique.
    # Defaults to 'stotfbrnd' + first 8 hex chars of the subscription ID,
    # giving a stable name that's unique per subscription (e.g. stotfbrnd71dcf7f8).
    # Override with -TfStateStorageAccount if needed.
    [Parameter(Mandatory=$false)]
    [string]$TfStateStorageAccount = "",

    [Parameter(Mandatory=$false)]
    [string]$TfStateResourceGroup = "rg-tfstate-brnd",

    # Run New-GitHubOidc.ps1 to create/update the Entra app registration and
    # set the 3 GitHub Actions secrets automatically. Requires 'gh' CLI.
    [Parameter(Mandatory=$false)]
    [switch]$SetupGitHub,

    # Skip Phase 0 (TF backend bootstrap) when the storage account and role
    # assignment already exist from a previous deploy.
    [Parameter(Mandatory=$false)]
    [switch]$SkipBootstrap
)

Set-StrictMode -Version Latest
Set-Variable -Name ErrorActionPreference -Value 'Stop'

$Action = if ($Destroy) { "destroy" } else { "all" }

# Import common functions
Import-Module "$PSScriptRoot\scripts\common\DeploymentFunctions.psm1" -Force

Write-Host @"

============================================================
  BrandSense - Deployment Orchestrator
============================================================

"@ -ForegroundColor Cyan

# Initialize Azure context
Initialize-AzureContext -Subscription $Subscription

# Resolve TfStateStorageAccount default from subscription ID (deterministic, unique per subscription)
if (-not $TfStateStorageAccount) {
    $subId = az account show --query id -o tsv 2>$null
    $suffix = ($subId -replace '-', '').Substring(0, 8).ToLower()
    $TfStateStorageAccount = "stotfbrnd$suffix"
}

# ---------------------------------------------------------------------------
# PHASE 0: Bootstrap Terraform remote state backend
# (idempotent — safe to run every deploy; skip with -SkipBootstrap after first run)
# Not needed for destroy — the backend must already exist.
# ---------------------------------------------------------------------------
if ($Destroy -or $SkipBootstrap) {
    Write-Host "`n=== PHASE 0: Skipped ===" -ForegroundColor DarkGray
} else {
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

# Assign Storage Blob Data Contributor to the current user BEFORE creating the
# container — subscription policy disables shared key access, so AAD data-plane
# permission must exist first. (idempotent)
$currentUserId = az ad signed-in-user show --query id -o tsv 2>$null
$storageId     = az storage account show `
                     --name $TfStateStorageAccount `
                     --resource-group $TfStateResourceGroup `
                     --query id -o tsv

if ($currentUserId -and $storageId) {
    Write-Host "  Assigning Storage Blob Data Contributor to current user (idempotent)..." -ForegroundColor Cyan
    # Suppress "RoleAssignmentExists" error - assignment is safe to re-create
    az role assignment create `
        --assignee $currentUserId `
        --role "Storage Blob Data Contributor" `
        --scope $storageId `
        --output none 2>&1 | Out-Null

    # Poll until the role is actually effective (RBAC can take up to 5 minutes to propagate)
    Write-Host "  Waiting for role assignment to propagate..." -ForegroundColor Gray
    $maxWait = 300
    $waited  = 0
    $interval = 10
    $ready = $false
    while (-not $ready -and $waited -lt $maxWait) {
        # Suppress stderr — az writes "ERROR:" while the role is still propagating,
        # which PowerShell treats as a fatal error under $ErrorActionPreference='Stop'.
        try {
            $null = az storage container list `
                --account-name $TfStateStorageAccount `
                --auth-mode login `
                --output none `
                --only-show-errors 2>$null
            if ($LASTEXITCODE -eq 0) { $ready = $true }
        } catch { }

        if (-not $ready) {
            Write-Host "  Still propagating... ($waited s elapsed)" -ForegroundColor Gray
            Start-Sleep -Seconds $interval
            $waited += $interval
        }
    }
    if (-not $ready) {
        Write-Host "WARNING: Role assignment may not have propagated after ${maxWait}s - continuing anyway." -ForegroundColor Yellow
    } else {
        Write-Host "  Role assignment effective after ${waited}s." -ForegroundColor Green
    }
}

az storage container create `
    --name tfstate `
    --account-name $TfStateStorageAccount `
    --auth-mode login `
    --output none

Write-Host "State backend ready." -ForegroundColor Green
} # end -not SkipBootstrap

# ---------------------------------------------------------------------------
# PHASE 1: Deploy Infrastructure (Terraform)
# ---------------------------------------------------------------------------
Write-Host "`n=== PHASE 1: Infrastructure Deployment ===" -ForegroundColor Magenta

# Resolve the GitHub Actions SP object ID (if the app registration exists) so
# Terraform can grant it the required data-plane roles (KV, AI, Search).
$githubSpObjectId = ""
$ghApp = az ad app list --display-name "sp-brnd-github" --query "[0].appId" -o tsv 2>$null
if ($ghApp) {
    $githubSpObjectId = az ad sp show --id $ghApp --query id -o tsv 2>$null
    if ($githubSpObjectId) {
        Write-Host "  GitHub SP object ID: $githubSpObjectId" -ForegroundColor Gray
    }
}

& "$PSScriptRoot\scripts\Deploy-Infrastructure.ps1" `
    -Action $Action `
    -Subscription $Subscription `
    -Location $Location `
    -Environment $Environment `
    -TfStateStorageAccount $TfStateStorageAccount `
    -GitHubSpObjectId $githubSpObjectId `
    -AutoApprove

if ($LASTEXITCODE -ne 0) {
    Write-Host "Infrastructure deployment failed" -ForegroundColor Red
    exit 1
}

# Nothing more to do after a destroy
if ($Destroy) {
    Write-Host "`n============================================================" -ForegroundColor Green
    Write-Host "      BrandSense infrastructure destroyed." -ForegroundColor Green
    Write-Host "============================================================`n" -ForegroundColor Green
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
    Write-Host "WARNING: Could not read Terraform outputs - Phases 1.5-4 may be skipped." -ForegroundColor Yellow
    $tfOutputs = $null
}

Pop-Location

$resourceGroupName   = if ($tfOutputs) { $tfOutputs.resource_group_name.value }         else { $null }
$keyVaultName        = if ($tfOutputs) { $tfOutputs.key_vault_name.value }               else { $null }
$searchEndpoint      = if ($tfOutputs) { $tfOutputs.search_service_endpoint.value }      else { $null }
$aiAccountName       = if ($tfOutputs) { $tfOutputs.ai_account_name.value }              else { $null }
$aiProjectName       = if ($tfOutputs) { $tfOutputs.ai_project_name.value }              else { $null }
$containerAppUrl     = if ($tfOutputs -and $tfOutputs.PSObject.Properties['container_app_url']) {
                           $tfOutputs.container_app_url.value
                       } else { '' }
$containerAppUiUrl   = if ($tfOutputs -and $tfOutputs.PSObject.Properties['container_app_ui_url']) {
                           $tfOutputs.container_app_ui_url.value
                       } else { '' }

# Derive Foundry project endpoint from account + project name
$aiProjectEndpoint = $null
if ($aiAccountName -and $aiProjectName) {
    $aiProjectEndpoint = "https://${aiAccountName}.services.ai.azure.com/api/projects/$aiProjectName"
}

if ($resourceGroupName)  { Write-Host "  Resource Group      : $resourceGroupName"  -ForegroundColor Gray }
if ($keyVaultName)       { Write-Host "  Key Vault           : $keyVaultName"        -ForegroundColor Gray }
if ($searchEndpoint)     { Write-Host "  Search Endpoint     : $searchEndpoint"      -ForegroundColor Gray }
if ($aiProjectEndpoint)  { Write-Host "  AI Project Endpoint : $aiProjectEndpoint"   -ForegroundColor Gray }
if ($containerAppUrl) {
    Write-Host "  Container App URL   : $containerAppUrl" -ForegroundColor Gray
}
if ($containerAppUiUrl) {
    Write-Host "  UI App URL          : $containerAppUiUrl" -ForegroundColor Gray
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
    Write-Host "WARNING: ACR name or resource group not available from Terraform outputs - skipping image build." -ForegroundColor Yellow
    Write-Host '         Build manually: .\scripts\Deploy-Containers.ps1 -ContainerRegistryName <name> -ResourceGroupName <rg>' -ForegroundColor Gray
} else {
    & "$PSScriptRoot\scripts\Deploy-Containers.ps1" `
        -ContainerRegistryName $acrName `
        -ResourceGroupName     $resourceGroupName

    if ($LASTEXITCODE -ne 0) {
        Write-Host "Container image build failed" -ForegroundColor Red
        exit 1
    }

    # Update both container apps to the real ACR images now that they exist
    $acrServer = $tfOutputs.container_registry_login_server.value
    Write-Host "`nUpdating container apps to real ACR images..." -ForegroundColor Cyan

    $caUpdates = @(
        @{ Name = 'brnd-api'; Image = "$acrServer/brnd-api:latest"; EnvVars = @() },
        @{ Name = 'brnd-ui';  Image = "$acrServer/brnd-ui:latest";  EnvVars = @() }
    )
    foreach ($ca in $caUpdates) {
        Write-Host "  Updating $($ca.Name) -> $($ca.Image)" -ForegroundColor Gray
        $updateArgs = @(
            'containerapp', 'update',
            '--name',           $ca.Name,
            '--resource-group', $resourceGroupName,
            '--image',          $ca.Image
        )
        if ($ca.EnvVars -and $ca.EnvVars.Count -gt 0) {
            Write-Host "    Setting env: $($ca.EnvVars -join ', ')" -ForegroundColor Gray
            $updateArgs += '--set-env-vars'
            $updateArgs += $ca.EnvVars
        }
        az @updateArgs | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "WARNING: Failed to update $($ca.Name) - the placeholder will remain until next deploy." -ForegroundColor Yellow
        }
    }
}

# ---------------------------------------------------------------------------
# PHASE 2: Seed AI Search guidelines index
# ---------------------------------------------------------------------------
Write-Host "`n=== PHASE 2: Seed Guidelines Index ===" -ForegroundColor Magenta

if (-not $searchEndpoint) {
    Write-Host "WARNING: search_service_endpoint not available from Terraform outputs - skipping." -ForegroundColor Yellow
} else {
    # Check Python
    try {
        $pyVer = python --version 2>&1
        Write-Host "Python found: $pyVer" -ForegroundColor Green
    } catch {
        Write-Host "WARNING: Python not found - skipping guidelines seeding." -ForegroundColor Yellow
        $searchEndpoint = $null
    }

    if ($searchEndpoint) {
        Write-Host "Installing guidelines dependencies..." -ForegroundColor Yellow
        pip install -r "$PSScriptRoot\scripts\load\requirements.txt" --quiet
        if ($LASTEXITCODE -ne 0) { throw "pip install (guidelines) failed." }

        Write-Host "Seeding brandsense-guidelines index..." -ForegroundColor Yellow
        $env:AZURE_SEARCH_ENDPOINT = $searchEndpoint
        # Pass OpenAI endpoint so the integrated vectorizer is configured on the index.
        # The format used by the AI Services (Foundry) account.
        if ($aiAccountName) {
            $env:AZURE_OPENAI_ENDPOINT = "https://${aiAccountName}.cognitiveservices.azure.com/"
        }
        python "$PSScriptRoot\scripts\load\guidelines.py"

        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] Guidelines index seeded." -ForegroundColor Green
        } else {
            Write-Host "WARNING: Guidelines seeding failed (exit $LASTEXITCODE) - continuing." -ForegroundColor Yellow
        }
    }
}

# ---------------------------------------------------------------------------
# PHASE 3: Deploy Foundry Agents
# ---------------------------------------------------------------------------
Write-Host "`n=== PHASE 3: Deploy Foundry Agents ===" -ForegroundColor Magenta

if (-not $aiProjectEndpoint -or -not $keyVaultName) {
    Write-Host 'WARNING: AI project endpoint or Key Vault name not available - skipping agent deployment.' -ForegroundColor Yellow
    Write-Host '         Run manually: .\scripts\Deploy-FoundryAgents.ps1 -AiProjectEndpoint <url> -KeyVaultName <name>' -ForegroundColor Gray
} else {
    & "$PSScriptRoot\scripts\Deploy-FoundryAgents.ps1" `
        -AiProjectEndpoint  $aiProjectEndpoint `
        -KeyVaultName       $keyVaultName `
        -SearchConnectionName "brandsense-search"

    if ($LASTEXITCODE -ne 0) {
        Write-Host "WARNING: Agent deployment failed (exit $LASTEXITCODE) - continuing." -ForegroundColor Yellow
    } else {
        Write-Host "[OK] Foundry agents deployed." -ForegroundColor Green
    }
}

# ---------------------------------------------------------------------------
# PHASE 3.5: Inject Foundry config into brnd-api Container App
# After Phase 3 writes agent IDs to Key Vault, read them back and set the
# env vars that pipeline.py needs to call the deployed agents at runtime.
# ---------------------------------------------------------------------------
Write-Host "`n=== PHASE 3.5: Configure brnd-api Foundry Environment ===" -ForegroundColor Magenta

if (-not $aiProjectEndpoint -or -not $keyVaultName -or -not $resourceGroupName) {
    Write-Host "WARNING: Missing AI project endpoint, Key Vault, or resource group - skipping Foundry env var injection." -ForegroundColor Yellow
} else {
    Write-Host "  Reading agent IDs from Key Vault ($keyVaultName)..." -ForegroundColor Gray
    $researcherAgentId = az keyvault secret show --vault-name $keyVaultName --name brandsense-researcher-agent-id --query value -o tsv 2>$null
    $auditorAgentId    = az keyvault secret show --vault-name $keyVaultName --name brandsense-auditor-agent-id    --query value -o tsv 2>$null
    $brieferAgentId    = az keyvault secret show --vault-name $keyVaultName --name brandsense-briefer-agent-id    --query value -o tsv 2>$null

    if (-not $researcherAgentId -or -not $auditorAgentId -or -not $brieferAgentId) {
        Write-Host "WARNING: Could not read all agent IDs from Key Vault - skipping env var injection." -ForegroundColor Yellow
        Write-Host "         Run Deploy-FoundryAgents.ps1 to deploy agents first." -ForegroundColor Gray
    } else {
        Write-Host "  Agent IDs:" -ForegroundColor Gray
        Write-Host "    Researcher : $researcherAgentId" -ForegroundColor Gray
        Write-Host "    Auditor    : $auditorAgentId"    -ForegroundColor Gray
        Write-Host "    Briefer    : $brieferAgentId"    -ForegroundColor Gray

        Write-Host "  Updating brnd-api container app with Foundry env vars..." -ForegroundColor Cyan
        az containerapp update `
            --name brnd-api `
            --resource-group $resourceGroupName `
            --set-env-vars `
                "FOUNDRY_PROJECT_CONNECTION_STRING=$aiProjectEndpoint" `
                "RESEARCHER_AGENT_ID=$researcherAgentId" `
                "AUDITOR_AGENT_ID=$auditorAgentId" `
                "BRIEFER_AGENT_ID=$brieferAgentId" | Out-Null

        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] Foundry env vars injected into brnd-api." -ForegroundColor Green
        } else {
            Write-Host "WARNING: Failed to update brnd-api env vars (exit $LASTEXITCODE)." -ForegroundColor Yellow
        }
    }
}

# ---------------------------------------------------------------------------
# PHASE 4: Configure GitHub Actions OIDC secrets (optional, -SetupGitHub)
# ---------------------------------------------------------------------------
$githubOidcConfigured = $false

if ($SetupGitHub) {
    Write-Host "`n=== PHASE 4: GitHub Actions OIDC Setup ===" -ForegroundColor Magenta

    # Verify gh CLI is available
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Write-Host "WARNING: 'gh' CLI not found - skipping GitHub secret setup." -ForegroundColor Yellow
        Write-Host "         Install from https://cli.github.com then re-run with -SetupGitHub" -ForegroundColor Gray
    } else {
        & "$PSScriptRoot\scripts\New-GitHubOidc.ps1"

        if ($LASTEXITCODE -eq 0) {
            $githubOidcConfigured = $true
        Write-Host "[OK] GitHub OIDC configured - secrets written to repo." -ForegroundColor Green
        } else {
            Write-Host "WARNING: GitHub OIDC setup failed (exit ${LASTEXITCODE}) - continuing." -ForegroundColor Yellow
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
Write-Host "[WARN] ACTION REQUIRED: Manually configure APIM MCP Server in the portal" -ForegroundColor Yellow
Write-Host "       APIM -> APIs -> MCP Servers -> Create -> Expose an API as an MCP server" -ForegroundColor Yellow
Write-Host "       Import OpenAPI spec from: https://${containerAppUrl}/openapi.json" -ForegroundColor Yellow
Write-Host ""
Write-Host "[WARN] ACTION REQUIRED: Add the APIM MCP endpoint to brandsense-auditor in Foundry" -ForegroundColor Yellow
Write-Host "       Foundry -> Agents -> brandsense-auditor -> Tools -> Add tool (MCP)" -ForegroundColor Yellow

Write-Host "`n=== Next Steps ===" -ForegroundColor Cyan

Write-Host "* Get the APIM MCP endpoint after manual portal setup:" -ForegroundColor Gray
Write-Host "* Verify agents in Foundry portal -> Agents (researcher / auditor / briefer)" -ForegroundColor Gray

Write-Host "`n=== GitHub Actions Secrets ===" -ForegroundColor Cyan
if ($githubOidcConfigured) {
    Write-Host "  [OK] OIDC configured - AZURE_CLIENT_ID / TENANT_ID / SUBSCRIPTION_ID written to repo." -ForegroundColor Green
} else {
    Write-Host "  Not configured. Re-run with -SetupGitHub to do this automatically, or run manually:" -ForegroundColor Yellow
    Write-Host "    .\scripts\New-GitHubOidc.ps1" -ForegroundColor White
    Write-Host "  Requires: az login + gh auth login" -ForegroundColor Gray
}


Write-Host "`n=== Service Endpoints ===" -ForegroundColor Cyan

if ($containerAppUrl -and $containerAppUrl -ne '') {
    Write-Host "  API : ${containerAppUrl}/docs" -ForegroundColor Green
}
if ($containerAppUiUrl -and $containerAppUiUrl -ne '') {
    Write-Host "  UI  : ${containerAppUiUrl}"    -ForegroundColor Cyan
}
if (-not $containerAppUrl -and -not $containerAppUiUrl) {
    Write-Host "  Endpoints not yet available - run: terraform output container_app_url" -ForegroundColor Yellow
}
Write-Host @"

============================================================
      BrandSense Deployment Complete!
============================================================

"@ -ForegroundColor Green
