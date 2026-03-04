# Deploy APIM Configuration
# APIs, operations, policies, tags, and named values are managed via Terraform (apim module).
# This script is reserved for any post-Terraform APIM steps that require runtime context.

param (
    [Parameter(Mandatory=$true)]
    [string]$Subscription,

    [Parameter(Mandatory=$false)]
    [string]$Environment = "dev"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module "$PSScriptRoot\common\DeploymentFunctions.psm1" -Force

Write-Host "`n=== PHASE 2: APIM Configuration ===" -ForegroundColor Magenta
Write-Host "APIM resources are fully managed by Terraform. No additional steps required." -ForegroundColor Green
exit 0
