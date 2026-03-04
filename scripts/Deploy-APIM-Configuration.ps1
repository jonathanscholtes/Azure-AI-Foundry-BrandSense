# Deploy APIM Configuration - Secrets and Named Values
# This script handles secrets deployment to Key Vault
# APIs, operations, policies, and tags are managed via Terraform in the apim_apis module

param (
    [Parameter(Mandatory=$true)]
    [string]$Subscription,
    
    [Parameter(Mandatory=$false)]
    [string]$HaloApiKey,
    
    [Parameter(Mandatory=$false)]
    [string]$Environment = "dev"
)

Set-StrictMode -Version Latest
Set-Variable -Name ErrorActionPreference -Value 'Stop'

# Import common functions
Import-Module "$PSScriptRoot\common\DeploymentFunctions.psm1" -Force

function Get-InfraOutputs {
    Write-Info "Retrieving Terraform outputs..."
    
    try {
        $outputs = & terraform -chdir="$PSScriptRoot\..\infra" output -json 2>$null | ConvertFrom-Json
        
        if (-not $outputs) {
            throw "Failed to retrieve Terraform outputs"
        }
        
        return $outputs
    } catch {
        Write-Error "Could not retrieve infrastructure outputs: $_"
        return $null
    }
}

function Deploy-Secrets {
    param (
        [PSCustomObject]$Outputs,
        [string]$HaloApiKey
    )
    
    Write-Title "Deploying Secrets to Key Vault"
    
    if (-not $Outputs -or -not $Outputs.key_vault_name) {
        Write-Error "Key Vault name not found in Terraform outputs"
        return $null
    }
    
    $keyVaultName = $Outputs.key_vault_name.value
    Write-Success "Found Key Vault: $keyVaultName"
    
    # Handle Halo API Key
    if ([string]::IsNullOrEmpty($HaloApiKey)) {
        Write-Info "No HaloApiKey provided. Checking environment variable..."
        $HaloApiKey = $env:HALO_API_KEY
    }
    
    if ([string]::IsNullOrEmpty($HaloApiKey)) {
        Write-Info "Prompting for halo-api-key (or press Enter to skip)..."
        $secureInput = Read-Host "Enter halo-api-key" -AsSecureString
        if ($secureInput.Length -gt 0) {
            $HaloApiKey = [System.Net.NetworkCredential]::new("", $secureInput).Password
        }
    }
    
    # Set Halo API Key in Key Vault if provided
    if (-not [string]::IsNullOrEmpty($HaloApiKey)) {
        Set-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "halo-api-key" -SecretValue $HaloApiKey
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to set halo-api-key secret"
            return $null
        }
        
        Write-Success "Secrets deployed successfully"
        return $keyVaultName
    } else {
        Write-Info "Skipping halo-api-key (no secret provided)"
        return $keyVaultName
    }
}

function Get-KeyVaultSecretUri {
    param (
        [string]$KeyVaultName,
        [string]$SecretName
    )
    
    Write-Info "Retrieving Key Vault secret URI..."
    
    try {
        # Get the secret metadata to retrieve its URI
        $secret = az keyvault secret show --vault-name $KeyVaultName --name $SecretName --query "id" -o tsv 2>$null
        
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrEmpty($secret)) {
            Write-Success "Found secret URI: $secret"
            return $secret
        } else {
            Write-Warning "Could not retrieve secret URI"
            return $null
        }
    } catch {
        Write-Warning "Failed to retrieve secret URI: $_"
        return $null
    }
}

function Update-TerraformForNamedValue {
    param (
        [string]$SecretUri,
        [string]$IdentityClientId
    )
    
    Write-Title "Creating APIM Named Value"
    
    Write-Info "Secret URI: $SecretUri"
    Write-Info "Identity Client ID: $IdentityClientId"
    
    Write-Host "`nTo create the APIM named value that references the Key Vault secret, run:" -ForegroundColor Cyan
    Write-Host @"
    
    cd infra
    terraform apply -var="key_vault_secret_identifier=$SecretUri" -var="identity_client_id=$IdentityClientId"
    cd ..
    
"@ -ForegroundColor Yellow
    
    Write-Host "This will create the 'halo-api-key' named value in APIM that references the secret." -ForegroundColor Cyan
}

# Main execution
try {
    Write-Host "`n=== PHASE 2: Secrets & APIM Configuration ===" -ForegroundColor Magenta
    
    # Get infrastructure outputs
    $outputs = Get-InfraOutputs
    if (-not $outputs) {
        Write-Error "Failed to retrieve infrastructure outputs"
        exit 1
    }
    
    # Deploy secrets
    $keyVaultName = Deploy-Secrets -Outputs $outputs -HaloApiKey $HaloApiKey
    if (-not $keyVaultName) {
        Write-Error "Failed to deploy secrets"
        exit 1
    }
    
    # Get secret URI and identity client ID for subsequent Terraform apply
    $secretUri = Get-KeyVaultSecretUri -KeyVaultName $keyVaultName -SecretName "halo-api-key"
    
    if ($secretUri -and $outputs.managed_identity_client_id) {
        $identityClientId = $outputs.managed_identity_client_id.value
        Update-TerraformForNamedValue -SecretUri $secretUri -IdentityClientId $identityClientId
    }
    
    Write-Success "Secrets deployment completed successfully"
    exit 0
}
catch {
    Write-Error "Secrets deployment failed: $_"
    exit 1
}
