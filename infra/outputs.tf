# Resource Group Outputs
output "resource_group_id" {
  description = "ID of the created resource group"
  value       = module.resource_group.id
}

output "resource_group_name" {
  description = "Name of the created resource group"
  value       = module.resource_group.name
}

# Storage Account Outputs
output "storage_account_id" {
  description = "ID of the storage account"
  value       = module.storage.id
}

output "storage_account_name" {
  description = "Name of the storage account"
  value       = module.storage.name
}

# Container Registry Outputs
output "container_registry_id" {
  description = "ID of the container registry"
  value       = module.container_registry.id
}

output "container_registry_login_server" {
  description = "Login server of the container registry"
  value       = module.container_registry.login_server
}

# Key Vault Outputs
output "key_vault_id" {
  description = "ID of the Key Vault"
  value       = module.key_vault.id
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = module.key_vault.vault_uri
}

output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = module.key_vault.name
}

# Search Service Outputs
output "search_service_id" {
  description = "ID of the AI Search service"
  value       = module.search.id
}

output "search_service_name" {
  description = "Name of the AI Search service"
  value       = module.search.name
}

output "search_service_endpoint" {
  description = "Endpoint of the AI Search service"
  value       = module.search.endpoint
}

# API Management Outputs
output "apim_id" {
  description = "ID of the API Management service"
  value       = module.apim.id
}

output "apim_name" {
  description = "Name of the API Management service"
  value       = module.apim.name
}

output "apim_gateway_url" {
  description = "Gateway URL of the API Management service"
  value       = module.apim.gateway_url
}

output "apim_management_api_url" {
  description = "Management API URL of the API Management service"
  value       = module.apim.management_api_url
}

output "apim_portal_url" {
  description = "Portal URL of the API Management service"
  value       = module.apim.portal_url
}

# AI Foundry Outputs
output "ai_account_id" {
  description = "ID of the AI Services account"
  value       = module.ai_services.ai_account_id
}

output "ai_account_endpoint" {
  description = "Endpoint of the AI Services account"
  value       = module.ai_services.ai_account_endpoint
}

output "ai_account_name" {
  description = "Name of the AI Services account"
  value       = module.ai_services.ai_account_name
}

output "openai_endpoint" {
  description = "OpenAI endpoint for the AI Services account"
  value       = module.ai_services.openai_endpoint
}

output "ai_project_id" {
  description = "ID of the AI Project"
  value       = module.ai_services.ai_project_id
}

output "ai_project_name" {
  description = "Name of the AI Project"
  value       = module.ai_services.ai_project_name
}

output "ai_project_endpoint" {
  description = "Endpoint URL for the AI Foundry project (azure-ai-projects SDK)"
  value       = module.ai_services.ai_project_endpoint
}

# Identity Outputs
output "managed_identity_id" {
  description = "ID of the user-assigned managed identity for all services"
  value       = module.identity.id
}

output "managed_identity_principal_id" {
  description = "Principal ID of the user-assigned managed identity"
  value       = module.identity.principal_id
}

output "managed_identity_client_id" {
  description = "Client ID of the user-assigned managed identity"
  value       = module.identity.client_id
}

# Container App Outputs
output "container_app_url" {
  description = "HTTPS URL of the BrandSense Container App"
  value       = module.container_apps.url
}

output "container_app_name" {
  description = "Name of the BrandSense Container App"
  value       = module.container_apps.name
}

output "container_app_ui_url" {
  description = "HTTPS URL of the BrandSense UI Container App"
  value       = module.container_apps_ui.url
}

output "container_app_ui_name" {
  description = "Name of the BrandSense UI Container App"
  value       = module.container_apps_ui.name
}

# Monitoring Outputs
output "app_insights_id" {
  description = "ID of Application Insights"
  value       = module.monitoring.id
}

output "app_insights_name" {
  description = "Name of Application Insights"
  value       = module.monitoring.name
}

output "app_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = module.monitoring.instrumentation_key
  sensitive   = true
}
