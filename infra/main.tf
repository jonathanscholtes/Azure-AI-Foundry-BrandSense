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
  semantic_search_sku   = var.semantic_search_sku
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
  container_app_url      = module.container_apps.url
  tags                   = local.common_tags
}

module "monitoring" {
  source = "./modules/monitoring"

  app_insights_name   = var.app_insights_name
  location            = module.resource_group.location
  resource_group_name = module.resource_group.name
  tags                = local.common_tags
}

data "azurerm_client_config" "current" {}

# Allow the deploying principal (CI or developer) to write to the Search index
# so the guidelines seeding script in deploy.ps1 can run without 403 errors.
resource "azurerm_role_assignment" "current_user_search_index_contributor" {
  scope                = module.search.id
  role_definition_name = "Search Index Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Allow deploying user to write agent IDs to Key Vault during deployment
resource "azurerm_role_assignment" "current_user_kv_secrets_officer" {
  scope                = module.key_vault.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Allow deploying user to create/manage Foundry agents
resource "azurerm_role_assignment" "current_user_ai_project_management" {
  scope              = module.ai_services.ai_account_id
  role_definition_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/eadc314b-1a2d-4efa-be10-5d325db5065e"
  principal_id       = data.azurerm_client_config.current.object_id

  depends_on = [module.ai_services]
}

# Allow deploying user to invoke agents and use AI services
resource "azurerm_role_assignment" "current_user_ai_user" {
  scope              = module.ai_services.ai_account_id
  role_definition_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/53ca6127-db72-4b80-b1b0-d745d6d5456d"
  principal_id       = data.azurerm_client_config.current.object_id

  depends_on = [module.ai_services]
}

# ---------------------------------------------------------------------------
# GitHub Actions service principal data-plane roles (optional)
# These mirror the deploying-user roles above, but target the CI/CD SP so
# that the deploy-agents, seed-guidelines, etc. workflow jobs succeed.
# ---------------------------------------------------------------------------
resource "azurerm_role_assignment" "github_sp_kv_secrets_officer" {
  count                = var.github_sp_object_id != "" ? 1 : 0
  scope                = module.key_vault.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = var.github_sp_object_id
}

resource "azurerm_role_assignment" "github_sp_search_index_contributor" {
  count                = var.github_sp_object_id != "" ? 1 : 0
  scope                = module.search.id
  role_definition_name = "Search Index Data Contributor"
  principal_id         = var.github_sp_object_id
}

resource "azurerm_role_assignment" "github_sp_ai_project_management" {
  count              = var.github_sp_object_id != "" ? 1 : 0
  scope              = module.ai_services.ai_account_id
  role_definition_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/eadc314b-1a2d-4efa-be10-5d325db5065e"
  principal_id       = var.github_sp_object_id
}

resource "azurerm_role_assignment" "github_sp_ai_user" {
  count              = var.github_sp_object_id != "" ? 1 : 0
  scope              = module.ai_services.ai_account_id
  role_definition_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/53ca6127-db72-4b80-b1b0-d745d6d5456d"
  principal_id       = var.github_sp_object_id
}

module "ai_services" {
  source = "./modules/ai_services"

  ai_account_name         = local.ai_account_name
  ai_project_name         = local.ai_project_name
  location                = module.resource_group.location
  resource_group_name     = module.resource_group.name
  subscription_id         = module.resource_group.subscription_id
  identity_id             = module.identity.id
  identity_principal_id   = module.identity.principal_id
  gpt41_capacity          = var.ai_services_deployment_gpt41_capacity
  embedding_capacity      = var.ai_services_deployment_embedding_capacity
  search_service_endpoint = "https://${var.search_service_name}.search.windows.net"
  search_service_id       = module.search.id
}

# Grant the AI Search service's system-assigned identity the Cognitive Services OpenAI User
# role so it can call text-embedding-ada-002 at query time for the integrated vectorizer.
# This enables vector_semantic_hybrid searches without client-side query embedding.
# count guards against the first apply before the identity exists in state.
resource "azurerm_role_assignment" "search_openai_user" {
  count              = module.search.principal_id != null ? 1 : 0
  scope              = module.ai_services.ai_account_id
  role_definition_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/53ca6127-db72-4b80-b1b0-d745d6d5456d"
  principal_id       = module.search.principal_id

  depends_on = [module.ai_services, module.search]
}

# Grant the Foundry AI Project's system-assigned identity the two roles required for
# keyless (AAD) AI Search tool calls inside agents.  Per the official docs at
# https://aka.ms/foundryazstroubleshooting, both roles are required:
#   • Search Index Data Contributor — execute queries against the index
#   • Search Service Contributor    — manage index-level operations
# Without these the tool call returns 400 "Access denied".
resource "azurerm_role_assignment" "ai_project_search_index_contributor" {
  scope                = module.search.id
  role_definition_name = "Search Index Data Contributor"
  principal_id         = module.ai_services.ai_project_principal_id

  depends_on = [module.ai_services, module.search]
}

resource "azurerm_role_assignment" "ai_project_search_service_contributor" {
  scope                = module.search.id
  role_definition_name = "Search Service Contributor"
  principal_id         = module.ai_services.ai_project_principal_id

  depends_on = [module.ai_services, module.search]
}

# Shared Container Apps Environment — both brnd-api and brnd-ui run in the same env
resource "azurerm_container_app_environment" "main" {
  name                = "cae-${var.project_name}-${var.environment}"
  location            = module.resource_group.location
  resource_group_name = module.resource_group.name
  tags                = local.common_tags
}

# Grant the managed identity AcrPull so Container Apps can pull images
resource "azurerm_role_assignment" "acr_pull" {
  scope                = module.container_registry.id
  role_definition_name = "AcrPull"
  principal_id         = module.identity.principal_id
}

module "container_apps" {
  source = "./modules/container_apps"

  container_app_name            = var.container_app_name
  container_app_image           = var.container_app_image
  container_app_environment_id  = azurerm_container_app_environment.main.id
  resource_group_name           = module.resource_group.name
  managed_identity_id           = module.identity.id
  managed_identity_client_id    = module.identity.client_id
  container_registry_server     = module.container_registry.login_server
  tags                          = local.common_tags

  depends_on = [azurerm_role_assignment.acr_pull]
}

module "container_apps_ui" {
  source = "./modules/container_apps"

  container_app_name            = var.container_app_ui_name
  container_app_image           = var.container_app_ui_image
  container_app_environment_id  = azurerm_container_app_environment.main.id
  resource_group_name           = module.resource_group.name
  managed_identity_id           = module.identity.id
  managed_identity_client_id    = module.identity.client_id
  container_registry_server     = module.container_registry.login_server
  # No extra env vars needed — nginx.conf has http://brnd-api hardcoded
  # (internal Container Apps DNS, same environment, no TLS).
  tags                          = local.common_tags

  depends_on = [azurerm_role_assignment.acr_pull]
}