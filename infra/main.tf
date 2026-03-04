terraform {
  # Partial backend configuration — storage account name is supplied at
  # 'terraform init' time via -backend-config so the same code works locally
  # and in GitHub Actions without committing secrets.
  #
  # Bootstrap the state backend once before first deploy:
  #   az group create -n rg-tfstate-brnd -l eastus2
  #   az storage account create -n <name> -g rg-tfstate-brnd --sku Standard_LRS
  #   az storage container create -n tfstate --account-name <name>
  #
  # Then init with:
  #   terraform init -backend-config="storage_account_name=<name>"
  backend "azurerm" {
    resource_group_name = "rg-tfstate-brnd"
    container_name      = "tfstate"
    key                 = "brandsense.tfstate"
    use_azuread_auth    = true
    # storage_account_name supplied via -backend-config at init time
  }
}

module "resource_group" {
  source = "./modules/resource_group"

  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = local.common_tags
}

module "identity" {
  source = "./modules/identity"

  managed_identity_name = var.managed_identity_name
  location              = module.resource_group.location
  resource_group_name   = module.resource_group.name
  tags                  = local.common_tags
}

module "storage" {
  source = "./modules/storage"

  storage_account_name      = var.storage_account_name
  location                  = module.resource_group.location
  resource_group_name       = module.resource_group.name
  storage_account_tier      = var.storage_account_tier
  storage_replication_type  = var.storage_replication_type
  storage_containers        = ["assets-raw", "assets-processed", "briefs-output"]
  identity_principal_id     = module.identity.principal_id
  tags                      = local.common_tags
}

module "key_vault" {
  source = "./modules/key_vault"

  key_vault_name           = var.key_vault_name
  location                 = module.resource_group.location
  resource_group_name      = module.resource_group.name
  tenant_id                = module.resource_group.tenant_id
  enable_purge_protection  = var.enable_purge_protection
  identity_principal_id    = module.identity.principal_id
  tags                     = local.common_tags
}

module "search" {
  source = "./modules/search"

  search_service_name   = var.search_service_name
  location              = module.resource_group.location
  resource_group_name   = module.resource_group.name
  search_sku            = var.search_sku
  identity_principal_id = module.identity.principal_id
  tags                  = local.common_tags
}

module "container_registry" {
  source = "./modules/container_registry"

  container_registry_name = var.container_registry_name
  location                = module.resource_group.location
  resource_group_name     = module.resource_group.name
  container_registry_sku  = var.container_registry_sku
  tags                    = local.common_tags
}

module "apim" {
  source = "./modules/apim"

  apim_name              = "apim-${var.project_name}-${var.environment}"
  location               = module.resource_group.location
  resource_group_name    = module.resource_group.name
  publisher_name         = var.apim_publisher_name
  publisher_email        = var.apim_publisher_email
  apim_sku               = var.apim_sku
  apim_sku_capacity      = var.apim_sku_capacity
  managed_identity_id    = module.identity.id
  tags                   = local.common_tags
}

module "monitoring" {
  source = "./modules/monitoring"

  app_insights_name   = var.app_insights_name
  location            = module.resource_group.location
  resource_group_name = module.resource_group.name
  tags                = local.common_tags
}

module "ai_services" {
  source = "./modules/ai_services"

  ai_account_name        = local.ai_account_name
  ai_project_name        = local.ai_project_name
  location               = module.resource_group.location
  resource_group_name    = module.resource_group.name
  subscription_id        = module.resource_group.subscription_id
  identity_id            = module.identity.id
  identity_principal_id  = module.identity.principal_id
  gpt41_capacity         = var.ai_services_deployment_gpt41_capacity
  embedding_capacity     = var.ai_services_deployment_embedding_capacity
}

module "container_apps" {
  source = "./modules/container_apps"

  container_app_name          = var.container_app_name
  container_app_image         = var.container_app_image
  location                    = module.resource_group.location
  resource_group_name         = module.resource_group.name
  managed_identity_id         = module.identity.id
  managed_identity_client_id  = module.identity.client_id
  container_registry_server   = module.container_registry.login_server
  tags                        = local.common_tags
}