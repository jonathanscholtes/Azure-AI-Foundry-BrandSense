# Build and push BrandSense container images to Azure Container Registry
# Uses 'az acr build' (server-side build — no local Docker required)
#
# Images:
#   brnd-api  — Python FastAPI  (apps/services/brandsense-api/Dockerfile, context: repo root)
#   brnd-ui   — React/nginx     (apps/ui/Dockerfile, context: apps/ui/)

param (
    [Parameter(Mandatory=$true)]
    [string]$ContainerRegistryName,

    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,

    # Subset of images to build. Defaults to both.
    [Parameter(Mandatory=$false)]
    [ValidateSet("brnd-api", "brnd-ui")]
    [string[]]$Images = @("brnd-api", "brnd-ui"),

    # Image tag. Defaults to 'latest'.
    [Parameter(Mandatory=$false)]
    [string]$Tag = "latest"
)

$ErrorActionPreference = "Stop"

Write-Host "`n=== BrandSense: Build & Push Container Images ===" -ForegroundColor Cyan
Write-Host "  Registry       : $ContainerRegistryName" -ForegroundColor White
Write-Host "  Resource Group : $ResourceGroupName"     -ForegroundColor White
Write-Host "  Tag            : $Tag"                   -ForegroundColor White

# Ensure az CLI output stays UTF-8 on Windows
$env:PYTHONIOENCODING = 'utf-8'
$env:PYTHONUTF8      = '1'
chcp 65001 | Out-Null
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding          = [System.Text.Encoding]::UTF8

# Image build configurations
# 'context' is the directory sent as the build context to ACR (mirrors CI).
# 'dockerfile' is the absolute path — az acr build resolves --file from CWD, not context.
$repoRoot    = (Resolve-Path "$PSScriptRoot\..").Path
$imageConfigs = @{
    "brnd-api" = @{
        context    = $repoRoot
        dockerfile = (Join-Path $repoRoot "apps\services\brandsense-api\Dockerfile")
    }
    "brnd-ui"  = @{
        context    = (Join-Path $repoRoot "apps\ui")
        dockerfile = (Join-Path $repoRoot "apps\ui\Dockerfile")
    }
}

$failed = @()

foreach ($imageName in $Images) {
    $config = $imageConfigs[$imageName]
    $imageRef = "${imageName}:${Tag}"

    Write-Host "`nBuilding '$imageRef'..." -ForegroundColor Yellow
    Write-Host "  Dockerfile : $($config.dockerfile)" -ForegroundColor Gray
    Write-Host "  Context    : $($config.context)"    -ForegroundColor Gray

    $azArgs = @(
        'acr', 'build',
        '--resource-group', $ResourceGroupName,
        '--registry',       $ContainerRegistryName,
        '--file',           $config.dockerfile,
        '--image',          $imageRef,
        $config.context
    )

    # Start-Process keeps the real console handle (avoids cp1252 errors from az CLI)
    $proc = Start-Process -FilePath 'az' -ArgumentList $azArgs -NoNewWindow -Wait -PassThru

    if ($proc.ExitCode -ne 0) {
        Write-Host "FAILED to build '$imageRef' (exit $($proc.ExitCode))" -ForegroundColor Red
        $failed += $imageName
    } else {
        Write-Host "[OK] '$imageRef' pushed to $ContainerRegistryName" -ForegroundColor Green
    }
}

if ($failed.Count -gt 0) {
    throw "The following images failed to build: $($failed -join ', ')"
}

Write-Host "`n[OK] All images built and pushed successfully." -ForegroundColor Green
