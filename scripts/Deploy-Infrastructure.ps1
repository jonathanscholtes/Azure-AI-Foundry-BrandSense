# Deploy Azure Infrastructure using Terraform
# This script deploys all Azure resources (AI Foundry, AI Search, API Management, Storage, etc.)

param (
    [Parameter(Mandatory=$true)]
    [ValidateSet("init", "validate", "plan", "apply", "all", "destroy", "output", "fmt", "clean")]
    [string]$Action,
    
    [Parameter(Mandatory=$true)]
    [string]$Subscription,
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "eastus",
    
    [Parameter(Mandatory=$false)]
    [string]$Environment = "dev",

    [Parameter(Mandatory=$false)]
    [string]$TfStateStorageAccount = "",

    [Parameter(Mandatory=$false)]
    [switch]$AutoApprove
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import common functions
Import-Module "$PSScriptRoot\common\DeploymentFunctions.psm1" -Force

# Import Azure resources that exist but are missing from Terraform state
# (e.g. after a partial apply). Safe to call repeatedly — skips resources already in state.
function Import-ExistingResources {
    param(
        [string]$SubscriptionId,
        [string]$Environment
    )

    $resourceToken     = Get-ResourceToken -SubscriptionId $SubscriptionId
    $resourceGroupName = "rg-brnd-$Environment-$resourceToken"

    $imports = @(
        @{
            State  = 'azurerm_container_app_environment.main'
            AzArgs = @('containerapp', 'env', 'show', '--name', "cae-brnd-$Environment", '--resource-group', $resourceGroupName, '--query', 'id', '-o', 'tsv')
        },
        @{
            State  = 'module.container_apps.azurerm_container_app.main'
            AzArgs = @('containerapp', 'show', '--name', 'brnd-api', '--resource-group', $resourceGroupName, '--query', 'id', '-o', 'tsv')
        },
        @{
            State  = 'module.container_apps_ui.azurerm_container_app.main'
            AzArgs = @('containerapp', 'show', '--name', 'brnd-ui', '--resource-group', $resourceGroupName, '--query', 'id', '-o', 'tsv')
        }
    )

    # Snapshot current state once (avoids repeated terraform state list calls)
    $stateLines = & { $ErrorActionPreference = 'SilentlyContinue'; terraform state list 2>&1 } |
                    Where-Object { $_ -is [string] }

    foreach ($item in $imports) {
        if ($stateLines -contains $item.State) {
            Write-Host "  Already in state: $($item.State)" -ForegroundColor Gray
            continue
        }

        # Resolve Azure resource ID; silence stderr to avoid NativeCommandError
        $azIdLines = & { $ErrorActionPreference = 'SilentlyContinue'; az @($item.AzArgs) 2>&1 } |
                       Where-Object { $_ -is [string] }
        $azId = ($azIdLines -join '').Trim()
        if (-not $azId) {
            Write-Host "  Not found in Azure (skipping): $($item.State)" -ForegroundColor Gray
            continue
        }

        Write-Host "Importing $($item.State) into Terraform state..." -ForegroundColor Cyan
        & { $ErrorActionPreference = 'SilentlyContinue'; terraform import $item.State $azId 2>&1 } |
            ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -ne 0) {
            Write-Host "WARNING: Import of $($item.State) failed - continuing." -ForegroundColor Yellow
        }
    }
}

function New-TerraformVarsFile {
    param(
        [string]$SubscriptionId,
        [string]$Location,
        [string]$Environment,
        [string]$OutputPath = "."
    )
    
    Write-Title "Generating terraform.tfvars"
    
    try {
        # Get absolute path
        $absolutePath = (Resolve-Path -Path $OutputPath -ErrorAction Stop).Path
        Write-Info "Target directory: $absolutePath"
        
        # Verify directory exists
        if (-not (Test-Path -Path $absolutePath -PathType Container)) {
            Write-Error "Output directory does not exist: $absolutePath"
            return $false
        }
        
        $resourceToken = Get-ResourceToken -SubscriptionId $SubscriptionId
        
        # Load template
        $templatePath = Join-Path $PSScriptRoot "..\infra\terraform.tfvars.tpl"
        if (-not (Test-Path $templatePath)) {
            Write-Error "Template not found: $templatePath"
            return $false
        }
        
        Write-Info "Loading template from: $templatePath"
        $content = Get-Content -Path $templatePath -Raw
        
        # Replace variables using safe replacements
        $content = $content -replace '\$\{SubscriptionId\}', $SubscriptionId
        $content = $content -replace '\$\{Location\}', $Location
        $content = $content -replace '\$\{Environment\}', $Environment
        $content = $content -replace '\$\{ResourceToken\}', $resourceToken
        
        $tfvarsPath = Join-Path -Path $absolutePath -ChildPath "terraform.tfvars"
        Set-Content -Path $tfvarsPath -Value $content -Encoding UTF8 -Force -ErrorAction Stop
        
        if (Test-Path -Path $tfvarsPath) {
            Write-Success "terraform.tfvars created at: $tfvarsPath"
            Write-Info "Resource token: $resourceToken"
            return $true
        } else {
            Write-Error "Failed to create terraform.tfvars"
            return $false
        }
    }
    catch {
        Write-Error "Error creating terraform.tfvars: $_"
        return $false
    }
}

function Test-Prerequisites {
    Write-Title "Checking Prerequisites"
    
    $missingTools = @()
    
    # Check Terraform
    if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) {
        $missingTools += "Terraform"
    } else {
        $tfVersion = terraform --version
        Write-Success "Terraform installed"
        Write-Host $tfVersion[0] -ForegroundColor Gray
    }
    
    # Check Azure CLI
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        $missingTools += "Azure CLI"
    } else {
        $azVersion = az --version | Select-Object -First 1
        Write-Success "Azure CLI installed"
    }
    
    # Check Azure authentication
    try {
        $account = az account show --output json | ConvertFrom-Json
        Write-Success "Azure authentication verified"
        $shortId = $account.id.Substring(0, 8)
        Write-Host "Subscription: $($account.name) ($shortId...)" -ForegroundColor Gray
    } catch {
        $missingTools += "Azure CLI authentication (Run 'az login')"
    }
    
    if ($missingTools.Count -gt 0) {
        Write-Host "Missing prerequisites:" -ForegroundColor Red
        $missingTools | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
        return $false
    }
    
    Write-Success "All prerequisites met"
    return $true
}

function Invoke-TerraformApplyWithRetry {
    param(
        [string]$SuccessMessage = "Deployment applied successfully",
        [int]$MaxRetries = 3,
        [int]$DelaySeconds = 30
    )

    $retryCount = 0
    $applySuccess = $false

    while ($retryCount -lt $MaxRetries -and -not $applySuccess) {
        $retryCount++
        Write-Host ""
        Write-Host "Applying... (Attempt $retryCount of $MaxRetries)" -ForegroundColor Yellow

        # Re-plan on retries to avoid "Saved plan is stale" error
        if ($retryCount -gt 1) {
            Write-Host "Re-planning after partial apply..." -ForegroundColor Cyan
            terraform plan -out=tfplan
            if ($LASTEXITCODE -ne 0) {
                Write-Host "Re-plan failed" -ForegroundColor Red
                exit 1
            }
        }

        terraform apply tfplan
        if ($LASTEXITCODE -eq 0) {
            $applySuccess = $true
            Write-Success $SuccessMessage
            terraform output
        } else {
            if ($retryCount -lt $MaxRetries) {
                Write-Host "Deployment attempt $retryCount failed. Waiting $DelaySeconds seconds before retry..." -ForegroundColor Yellow
                Start-Sleep -Seconds $DelaySeconds
            } else {
                Write-Host "Deployment failed after $MaxRetries attempts" -ForegroundColor Red
                exit 1
            }
        }
    }
}

# Main execution
Write-Title "BrandSense - Infrastructure Deployment"

# Check prerequisites
if (-not (Test-Prerequisites)) {
    Write-Host "Prerequisites check failed" -ForegroundColor Red
    exit 1
}

# Authenticate and set subscription (idempotent; safe if parent already called)
Initialize-AzureContext -Subscription $Subscription
$subscriptionId = az account show --query id -o tsv

# Derive storage account name from subscription ID if not supplied
if (-not $TfStateStorageAccount) {
    $suffix = ($subscriptionId -replace '-', '').Substring(0, 8).ToLower()
    $TfStateStorageAccount = "stotfbrnd$suffix"
    Write-Info "TF state storage account: $TfStateStorageAccount"
}

# Change to infra directory (restore on exit via finally block)
$infraDir = Join-Path $PSScriptRoot "..\infra"
if (-not (Test-Path $infraDir)) {
    Write-Host "Infrastructure directory not found: $infraDir" -ForegroundColor Red
    exit 1
}

Push-Location -Path $infraDir

try {

# Generate terraform.tfvars for deployment actions
if ($Action -in @("init", "plan", "apply", "all", "validate")) {
    Write-Info "Generating terraform.tfvars..."
    if (-not (New-TerraformVarsFile -SubscriptionId $subscriptionId -Location $Location -Environment $Environment -OutputPath ".")) {
        Write-Host "Failed to generate terraform.tfvars" -ForegroundColor Red
        exit 1
    }
}

# Execute based on action
Write-Info "Executing terraform action: $Action"

switch ($Action.ToLower()) {
    "init" {
        Write-Title "Initializing Terraform"
        terraform init `
            -backend-config="storage_account_name=$TfStateStorageAccount" `
            -reconfigure
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Terraform initialization failed" -ForegroundColor Red
            exit 1
        }
        Write-Success "Terraform initialized successfully"
    }
    "validate" {
        Write-Title "Validating Terraform Configuration"
        terraform init `
            -backend-config="storage_account_name=$TfStateStorageAccount" `
            -reconfigure
        if ($LASTEXITCODE -ne 0) { exit 1 }

        terraform validate
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Configuration validation failed" -ForegroundColor Red
            exit 1
        }
        Write-Success "Configuration is valid"
    }
    "plan" {
        Write-Title "Planning Terraform Deployment"
        terraform init `
            -backend-config="storage_account_name=$TfStateStorageAccount" `
            -reconfigure
        if ($LASTEXITCODE -ne 0) { exit 1 }

        terraform validate
        if ($LASTEXITCODE -ne 0) { exit 1 }

        Write-Info "Generating execution plan..."
        terraform plan -out=tfplan
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Plan creation failed" -ForegroundColor Red
            exit 1
        }
        Write-Success "Plan created successfully"
    }
    "apply" {
        Write-Title "Applying Terraform Configuration"
        terraform init `
            -backend-config="storage_account_name=$TfStateStorageAccount" `
            -reconfigure
        if ($LASTEXITCODE -ne 0) { exit 1 }

        terraform validate
        if ($LASTEXITCODE -ne 0) { exit 1 }

        # Import any resources that exist in Azure but are absent from state
        Write-Info "Checking for state drift (importing orphaned resources)..."
        Import-ExistingResources -SubscriptionId $subscriptionId -Environment $Environment

        terraform plan -out=tfplan
        if ($LASTEXITCODE -ne 0) { exit 1 }

        if (-not $AutoApprove) {
            Write-Host "WARNING: This will create/modify Azure resources" -ForegroundColor Yellow
            $confirmation = Read-Host "Type 'yes' to confirm deployment"
            if ($confirmation -ne "yes") {
                Write-Host "Deployment cancelled" -ForegroundColor Yellow
                exit 0
            }
        }

        Write-Host "Applying infrastructure changes..." -ForegroundColor Cyan
        Write-Host "This may take 15-30 minutes (APIM deployment is slow)..." -ForegroundColor Cyan
        Invoke-TerraformApplyWithRetry -SuccessMessage "Deployment applied successfully"
    }
    "all" {
        Write-Title "Full Terraform Deployment"

        # Init
        Write-Info "Step 1/4: Initializing..."
        terraform init `
            -backend-config="storage_account_name=$TfStateStorageAccount" `
            -reconfigure
        if ($LASTEXITCODE -ne 0) { exit 1 }

        # Validate
        Write-Info "Step 2/4: Validating..."
        terraform validate
        if ($LASTEXITCODE -ne 0) { exit 1 }

        # Import any resources that exist in Azure but are absent from state
        Write-Info "Step 2.5/4: Checking for state drift (importing orphaned resources)..."
        Import-ExistingResources -SubscriptionId $subscriptionId -Environment $Environment

        # Plan
        Write-Info "Step 3/4: Planning..."
        terraform plan -out=tfplan
        if ($LASTEXITCODE -ne 0) { exit 1 }

        # Confirm before apply (unless -AutoApprove)
        if (-not $AutoApprove) {
            Write-Host "WARNING: Step 4/4 will apply infrastructure changes" -ForegroundColor Yellow
            $confirmation = Read-Host "Type 'yes' to confirm deployment"
            if ($confirmation -ne "yes") {
                Write-Host "Deployment cancelled" -ForegroundColor Yellow
                exit 0
            }
        }

        Write-Info "Step 4/4: Applying..."
        Write-Host "This may take 15-30 minutes (APIM deployment is slow)..." -ForegroundColor Cyan
        Invoke-TerraformApplyWithRetry -SuccessMessage "Full deployment completed successfully"
    }
    "destroy" {
        Write-Title "Destroying Resources"
        terraform init `
            -backend-config="storage_account_name=$TfStateStorageAccount" `
            -reconfigure
        if ($LASTEXITCODE -ne 0) { exit 1 }

        Write-Host "WARNING: All resources created by Terraform will be permanently deleted!" -ForegroundColor Red
        $confirmation = Read-Host "Type 'yes' to confirm resource deletion"
        if ($confirmation -ne "yes") {
            Write-Host "Destruction cancelled" -ForegroundColor Yellow
            exit 0
        }

        Write-Info "Destroying infrastructure..."
        terraform destroy -auto-approve
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Resources destroyed successfully"
        } else {
            Write-Host "Destruction failed" -ForegroundColor Red
            exit 1
        }
    }
    "output" {
        Write-Title "Deployment Outputs"
        terraform output
    }
    "fmt" {
        Write-Title "Formatting Terraform Code"
        terraform fmt -recursive
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Code formatted"
        } else {
            Write-Host "Code formatting failed" -ForegroundColor Red
            exit 1
        }
    }
    "clean" {
        Write-Title "Cleaning Local State"
        Write-Host "WARNING: This will remove local Terraform files!" -ForegroundColor Yellow

        $confirmation = Read-Host "Type 'yes' to confirm"
        if ($confirmation -eq "yes") {
            Write-Info "Removing Terraform state files and cache..."
            Remove-Item -Path ".terraform" -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path ".terraform.lock.hcl" -Force -ErrorAction SilentlyContinue
            Remove-Item -Path "tfplan" -Force -ErrorAction SilentlyContinue
            Remove-Item -Path "*.tfstate*" -Force -ErrorAction SilentlyContinue
            Write-Success "State cleaned"
        } else {
            Write-Host "Clean cancelled" -ForegroundColor Yellow
        }
    }
    default {
        Write-Host "Unknown action: $Action" -ForegroundColor Red
        exit 1
    }
}

} finally {
    Pop-Location
}

Write-Success "Action '$Action' completed successfully"
exit 0
