param (
    [Parameter(Mandatory = $true)]
    [string]$AiProjectEndpoint,

    [Parameter(Mandatory = $true)]
    [string]$KeyVaultName,

    [Parameter(Mandatory = $false)]
    [string]$ModelDeployment = "gpt-4.1",

    [Parameter(Mandatory = $false)]
    [string]$SearchConnectionName = "brandsense-search",

    # Deploy only the listed agents (e.g. "researcher", "auditor", "briefer").
    # When empty, deploys all agents.
    [Parameter(Mandatory = $false)]
    [string[]]$Only = @()
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
    Write-Host "Python not found - cannot deploy agents." -ForegroundColor Red
    throw "Python is required for agent deployment."
}

# ---------------------------------------------------------------------------
# 2. Install Python dependencies
# ---------------------------------------------------------------------------
Write-Host "`nInstalling Python dependencies..." -ForegroundColor Yellow
$repoRoot = Split-Path $PSScriptRoot -Parent
pip install -r "$repoRoot\agents\requirements.txt" --quiet
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
    "$repoRoot\agents\deploy.py",
    "--project-endpoint", $AiProjectEndpoint,
    "--model-deployment", $ModelDeployment,
    "--key-vault-name",   $KeyVaultName,
    "--search-connection-name", $SearchConnectionName
)

if ($Only.Count -gt 0) {
    $pythonArgs += "--only"
    $pythonArgs += $Only
}

python @pythonArgs

if ($LASTEXITCODE -ne 0) {
    throw "Agent deployment script failed (exit code $LASTEXITCODE)."
}

Write-Host "`n[OK] Foundry agents deployed and IDs written to Key Vault." -ForegroundColor Green
Write-Host "`n=== Done ===" -ForegroundColor Cyan
