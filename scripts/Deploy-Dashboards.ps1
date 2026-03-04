# Deploy-Dashboards.ps1
# Uploads Grafana dashboard JSON files to Azure Managed Grafana via the Grafana HTTP API.
# An access token is obtained from the current Azure CLI session using the Azure Managed
# Grafana application resource ID.

param (
    [Parameter(Mandatory = $true)]
    [string]$GrafanaUrl,

    [Parameter(Mandatory = $false)]
    [string]$DashboardsPath = "$PSScriptRoot\..\observability\dashboards",

    [Parameter(Mandatory = $false)]
    [string]$PrometheusUrl = ''
)

# ---------------------------------------------------------------------------
# Azure Managed Grafana application ID (constant across all tenants)
# ---------------------------------------------------------------------------
$GRAFANA_APP_ID = "ce34e7e5-485f-4d76-964f-b3d2b16d1e4f"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Write-Step {
    param([string]$Message)
    Write-Host "  --> $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "  [OK]  $Message" -ForegroundColor Green
}

function Write-Failure {
    param([string]$Message)
    Write-Host "  [FAIL] $Message" -ForegroundColor Red
}

# ---------------------------------------------------------------------------
# Validate inputs
# ---------------------------------------------------------------------------
Write-Host "`nDeploying Grafana dashboards..." -ForegroundColor Magenta

$resolvedPath = Resolve-Path $DashboardsPath -ErrorAction SilentlyContinue
if (-not $resolvedPath) {
    Write-Failure "Dashboards path not found: $DashboardsPath"
    exit 1
}

$dashboardFiles = @(Get-ChildItem -Path $resolvedPath -Filter "*.json")
if ($dashboardFiles.Count -eq 0) {
    Write-Host "  No dashboard JSON files found in $resolvedPath - skipping." -ForegroundColor Yellow
    exit 0
}

# Normalise URL (strip trailing slash)
$GrafanaUrl = $GrafanaUrl.TrimEnd("/")

Write-Step "Grafana endpoint : $GrafanaUrl"
Write-Step "Dashboards path  : $resolvedPath"
Write-Step "Dashboard files  : $($dashboardFiles.Count) found"

# ---------------------------------------------------------------------------
# Acquire bearer token via Azure CLI
# ---------------------------------------------------------------------------
Write-Step "Acquiring access token for Azure Managed Grafana..."

try {
    $tokenJson = az account get-access-token --resource $GRAFANA_APP_ID --output json 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "az account get-access-token failed: $tokenJson"
    }
    $token = ($tokenJson | ConvertFrom-Json).accessToken
    if ([string]::IsNullOrEmpty($token)) {
        throw "Token was empty. Ensure you are logged in with: az login"
    }
    Write-Success "Bearer token acquired."
}
catch {
    Write-Failure "Failed to acquire access token: $_"
    Write-Host "  Make sure you have run 'az login' and have Grafana Admin role on the resource." -ForegroundColor Yellow
    exit 1
}

$headers = @{
    "Authorization" = "Bearer $token"
    "Content-Type"  = "application/json"
}

# ---------------------------------------------------------------------------
# Configure Prometheus data source (Azure Monitor Workspace)
# ---------------------------------------------------------------------------
if (-not [string]::IsNullOrEmpty($PrometheusUrl)) {
    Write-Step "Configuring Prometheus data source pointing to Azure Monitor Workspace..."
    try {
        $dsPayload = @{
            name      = 'Prometheus'
            type      = 'prometheus'
            access    = 'proxy'
            url       = $PrometheusUrl
            isDefault = $true
            jsonData  = @{
                httpMethod       = 'POST'
                azureCredentials = @{ authType = 'msi' }
            }
        } | ConvertTo-Json -Depth 10

        $dsResponse = Invoke-RestMethod `
            -Method Post `
            -Uri "$GrafanaUrl/api/datasources" `
            -Headers $headers `
            -Body $dsPayload `
            -ErrorAction Stop
        Write-Success "Prometheus data source created (id: $($dsResponse.datasource.id))"
    }
    catch {
        # A 409 means it already exists - update it instead
        $exResponse = $_.Exception | Select-Object -ExpandProperty Response -ErrorAction SilentlyContinue
        if ($exResponse -and $exResponse.StatusCode.value__ -eq 409) {
            Write-Step "Data source already exists, updating..."
            try {
                $existing = Invoke-RestMethod -Method Get -Uri "$GrafanaUrl/api/datasources/name/Prometheus" -Headers $headers
                $dsPayload = @{
                    name      = 'Prometheus'
                    type      = 'prometheus'
                    access    = 'proxy'
                    url       = $PrometheusUrl
                    isDefault = $true
                    jsonData  = @{
                        httpMethod       = 'POST'
                        azureCredentials = @{ authType = 'msi' }
                    }
                } | ConvertTo-Json -Depth 10
                Invoke-RestMethod -Method Put -Uri "$GrafanaUrl/api/datasources/$($existing.id)" -Headers $headers -Body $dsPayload | Out-Null
                Write-Success "Prometheus data source updated."
            } catch {
                Write-Failure "Failed to update Prometheus data source: $_"
            }
        } else {
            Write-Failure "Failed to configure Prometheus data source: $_"
        }
    }
} else {
    Write-Host "  [SKIP] PrometheusUrl not provided - skipping data source configuration." -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# Build a datasource UID map: pluginId -> actual UID in this Grafana instance
# Used to resolve ${DS_*} template variables in imported dashboards.
# ---------------------------------------------------------------------------
$datasourceUidMap = @{}
try {
    $allDs = Invoke-RestMethod -Method Get -Uri "$GrafanaUrl/api/datasources" -Headers $headers -ErrorAction Stop
    foreach ($ds in $allDs) {
        if (-not $datasourceUidMap.ContainsKey($ds.type)) {
            $datasourceUidMap[$ds.type] = $ds.uid
        }
    }
    Write-Step "Fetched $($allDs.Count) datasource(s): $($datasourceUidMap.Keys -join ', ')"
}
catch {
    Write-Host "  [WARN] Could not fetch datasource list: $_" -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# Upload each dashboard
# ---------------------------------------------------------------------------
$successCount = 0
$failCount    = 0

foreach ($file in $dashboardFiles) {
    Write-Step "Uploading: $($file.Name)"

    try {
        $dashboardJson = Get-Content -Path $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json

        # Detect export format (has __inputs/__requires) vs raw dashboard format
        $isExportFormat = $null -ne $dashboardJson.__inputs

        if ($isExportFormat) {
            # Build datasource input bindings from __inputs
            # The 'value' must be the actual datasource UID in this Grafana instance,
            # not the plugin type name — otherwise Grafana returns "auth type 'undefined'".
            $inputs = @()
            foreach ($input in $dashboardJson.__inputs) {
                $resolvedUid = if ($input.type -eq 'datasource' -and $datasourceUidMap.ContainsKey($input.pluginId)) {
                    $datasourceUidMap[$input.pluginId]
                } else {
                    $input.pluginId  # fallback
                }
                $inputs += @{
                    name     = $input.name
                    type     = $input.type
                    pluginId = $input.pluginId
                    value    = $resolvedUid
                }
            }

            $payload = @{
                dashboard = $dashboardJson
                overwrite = $true
                inputs    = $inputs
                folderId  = 0
            } | ConvertTo-Json -Depth 100

            $uri = "$GrafanaUrl/api/dashboards/import"
        }
        else {
            # Raw dashboard format: strip id for create/overwrite
            $dashboardJson.PSObject.Properties.Remove("id")

            $payload = @{
                dashboard = $dashboardJson
                overwrite = $true
                folderId  = 0
            } | ConvertTo-Json -Depth 100

            $uri = "$GrafanaUrl/api/dashboards/db"
        }

        $response = Invoke-RestMethod `
            -Method Post `
            -Uri $uri `
            -Headers $headers `
            -Body $payload `
            -ErrorAction Stop

        Write-Success "Uploaded '$($file.Name)' -> uid: $($response.uid)  url: $GrafanaUrl$($response.url)"
        $successCount++
    }
    catch {
        $exResponse = $_.Exception | Select-Object -ExpandProperty Response -ErrorAction SilentlyContinue
        $statusCode = if ($exResponse) { $exResponse.StatusCode.value__ } else { 'N/A' }
        Write-Failure "Failed to upload '$($file.Name)' (HTTP $statusCode): $_"
        $failCount++
    }
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "  Dashboards uploaded : $successCount" -ForegroundColor $(if ($successCount -gt 0) { "Green" } else { "Yellow" })
if ($failCount -gt 0) {
    Write-Host "  Dashboards failed   : $failCount" -ForegroundColor Red
    exit 1
}
