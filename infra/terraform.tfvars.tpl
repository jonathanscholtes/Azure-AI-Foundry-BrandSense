subscription_id     = "${SubscriptionId}"
location            = "${Location}"
environment         = "${Environment}"
project_name        = "brnd"
resource_token      = "${ResourceToken}"
resource_group_name = "rg-brnd-${Environment}-${ResourceToken}"

# AI Hub / Project
ai_hub_name     = "aihub-brnd-${ResourceToken}"
ai_project_name = "aiproject-brnd-${ResourceToken}"

# Search Service
search_service_name = "search-brnd-${ResourceToken}"
search_sku          = "basic"

# API Management
apim_publisher_name  = "BrandSense"
apim_publisher_email = "admin@brandsense.com"
apim_sku             = "Developer"
apim_sku_capacity    = 1

# Storage
storage_account_name    = "stobrnd${ResourceToken}"
container_registry_name = "acrbrnd${ResourceToken}"
key_vault_name          = "kv-brnd-${ResourceToken}"

# Container Apps
# Placeholder images are used on first deploy; Phase 1.5 updates to real ACR images.
container_app_name     = "brnd-api"
container_app_image    = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
container_app_ui_name  = "brnd-ui"
container_app_ui_image = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"

# Tags
tags = {
  Environment = "${Environment}"
  Project     = "BrandSense"
  ManagedBy   = "Terraform"
}
