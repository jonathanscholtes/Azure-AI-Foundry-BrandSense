# Common deployment functions for Contract Risk MCP Platform
# This module contains shared utilities used across deployment scripts

# Helper functions for formatted output
function Write-Title {
    param([string]$Title)
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host $Title -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Success {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Initialize-AzureContext {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Subscription
    )
    
    Write-Host "`n=== Initializing Azure Context ===" -ForegroundColor Cyan
    
    # Configure Azure CLI settings
    az config set core.enable_broker_on_windows=false | Out-Null
    az config set core.login_experience_v2=off | Out-Null
    
    # Check current authentication
    try {
        $currentAccount = az account show --query "id" -o tsv 2>$null
        if ($currentAccount) {
            Write-Host "[OK] Already authenticated" -ForegroundColor Green
        } else {
            throw "Not authenticated"
        }
    } catch {
        Write-Host "Logging into Azure..." -ForegroundColor Cyan
        az login | Out-Null
    }
    
    # Set subscription
    az account set --subscription $Subscription
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to set subscription to $Subscription"
    }
    
    Write-Host "[OK] Connected to subscription: $Subscription" -ForegroundColor Green
}

function Test-RequiredTools {
    param (
        [string[]]$Tools = @("kubectl", "helm", "kubelogin")
    )
    
    Write-Host "`n=== Checking Required Tools ===" -ForegroundColor Cyan
    
    $missingTools = @()
    
    # Define installation instructions
    $installationGuide = @{
        'kubectl'  = 'az aks install-cli'
        'helm'     = 'winget install Helm.Helm'
        'kubelogin' = 'az aks install-cli'
        'python'   = 'winget install Python.Python.3.11'
    }
    
    foreach ($tool in $Tools) {
        if (Get-Command $tool -ErrorAction SilentlyContinue) {
            Write-Host "[OK] $tool found" -ForegroundColor Green
        } else {
            Write-Host "[X] $tool not found" -ForegroundColor Red
            $missingTools += $tool
        }
    }
    
    if ($missingTools.Count -gt 0) {
        Write-Host "`n[X] Missing required tools: $($missingTools -join ', ')" -ForegroundColor Red
        Write-Host "`nInstallation instructions:" -ForegroundColor Yellow
        
        foreach ($tool in $missingTools) {
            if ($installationGuide.ContainsKey($tool)) {
                Write-Host "`n${tool}:" -ForegroundColor White
                Write-Host "  $($installationGuide[$tool])" -ForegroundColor Gray
            }
        }
        
        throw "Missing required tools. Please install and retry."
    }
    
    Write-Host "All required tools found`n" -ForegroundColor Green
}

function Get-RandomAlphaNumeric {
    param (
        [int]$Length = 12,
        [string]$Seed
    )
    
    $base62Chars = "abcdefghijklmnopqrstuvwxyz123456789"
    
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $seedBytes = [System.Text.Encoding]::UTF8.GetBytes($Seed)
    $hashBytes = $md5.ComputeHash($seedBytes)
    
    $randomString = ""
    for ($i = 0; $i -lt $Length; $i++) {
        $index = $hashBytes[$i % $hashBytes.Length] % $base62Chars.Length
        $randomString += $base62Chars[$index]
    }
    
    return $randomString
}

function New-SecurePassword {
    param (
        [int]$Length = 16
    )
    # Ensure minimum password length of 8
    if ($Length -lt 8) {
        $Length = 8
    }
    
    # Define character sets
    $lowercase = 'abcdefghijklmnopqrstuvwxyz'
    $uppercase = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    $numbers = '0123456789'
    
    # Ensure password contains at least one from each required category
    $password = @()
    $password += $lowercase[(Get-Random -Maximum $lowercase.Length)]
    $password += $uppercase[(Get-Random -Maximum $uppercase.Length)]
    $password += $numbers[(Get-Random -Maximum $numbers.Length)]
    
    # Fill remaining length with random characters from all sets
    $allChars = $lowercase + $uppercase + $numbers
    for ($i = $password.Count; $i -lt $Length; $i++) {
        $password += $allChars[(Get-Random -Maximum $allChars.Length)]
    }
    
    # Shuffle the password to avoid predictable pattern
    $shuffled = $password | Get-Random -Count $password.Count
    return -join $shuffled
}

function Invoke-HelmWithRetry {
    param (
        [string]$CommandDescription,
        [scriptblock]$Command,
        [int]$MaxRetries = 3,
        [int]$DelaySeconds = 10
    )
    
    for ($i = 1; $i -le $MaxRetries; $i++) {
        try {
            Write-Host "Attempt $i of $MaxRetries..." -ForegroundColor Gray
            
            # Execute the command directly (no buffering)
            & $Command
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "[OK] $CommandDescription completed successfully" -ForegroundColor Green
                return $true
            }
            
            Write-Host "Command exited with code $LASTEXITCODE" -ForegroundColor Yellow
        }
        catch {
            Write-Host "Error: $_" -ForegroundColor Yellow
        }
        
        if ($i -lt $MaxRetries) {
            Write-Host "Retrying in $DelaySeconds seconds..." -ForegroundColor Yellow
            Start-Sleep -Seconds $DelaySeconds
        }
    }
    
    Write-Host "[X] $CommandDescription failed after $MaxRetries attempts" -ForegroundColor Red
    return $false
}

function Get-ServiceExternalIP {
    param (
        [string]$ServiceName,
        [string]$Namespace = "tools",
        [int]$MaxWaitSeconds = 180
    )
    
    $waited = 0
    while ($waited -lt $MaxWaitSeconds) {
        $externalIP = (kubectl get svc $ServiceName -n $Namespace -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null)
        if (![string]::IsNullOrWhiteSpace($externalIP) -and $externalIP -ne "<pending>") {
            return $externalIP.Trim()
        }
        Start-Sleep -Seconds 10
        $waited += 10
        Write-Host "  Waiting for $ServiceName IP... (${waited}/${MaxWaitSeconds} seconds)" -ForegroundColor Gray
    }
    return $null
}

function New-FederatedIdentityCredential {
    param (
        [string]$ServiceAccountName,
        [string]$Namespace = "tools",
        [string]$ManagedIdentityName,
        [string]$ResourceGroupName,
        [string]$OidcIssuer
    )
    
    $credentialName = "${ServiceAccountName}-federated-id"
    $subject = "system:serviceaccount:${Namespace}:${ServiceAccountName}"
    
    $existingCred = az identity federated-credential show `
        --name $credentialName `
        --identity-name $ManagedIdentityName `
        --resource-group $ResourceGroupName `
        --output none `
        2>$null
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Creating federated identity credential for $ServiceAccountName..." -ForegroundColor Yellow
        az identity federated-credential create `
            --name $credentialName `
            --identity-name $ManagedIdentityName `
            --resource-group $ResourceGroupName `
            --issuer $OidcIssuer `
            --subject $subject `
            --audience "api://AzureADTokenExchange" `
            --output none
        Write-Host "Federated identity credential created for $ServiceAccountName" -ForegroundColor Green
    } else {
        Write-Host "Federated identity credential already exists for $ServiceAccountName" -ForegroundColor Green
    }
}

function Set-KeyVaultSecret {
    param (
        [Parameter(Mandatory=$true)]
        [string]$KeyVaultName,
        
        [Parameter(Mandatory=$true)]
        [string]$SecretName,
        
        [Parameter(Mandatory=$true)]
        [string]$SecretValue
    )
    
    Write-Title "Adding Secret to Key Vault: $SecretName"
    
    try {
        az keyvault secret set `
            --vault-name $KeyVaultName `
            --name $SecretName `
            --value $SecretValue | Out-Null
        
        Write-Success "Secret '$SecretName' added to Key Vault '$KeyVaultName'"
        return $true
    } catch {
        Write-Error "Failed to set secret: $_"
        return $false
    }
}

Export-ModuleMember -Function @(
    'Write-Title',
    'Write-Success',
    'Write-Info',
    'Initialize-AzureContext',
    'Get-RandomAlphaNumeric',
    'New-SecurePassword',
    'Invoke-HelmWithRetry',
    'Get-ServiceExternalIP',
    'New-FederatedIdentityCredential',
    'Set-KeyVaultSecret'
)
