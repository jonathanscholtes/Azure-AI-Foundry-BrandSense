output "id" {
  description = "ID of the API Management service"
  value       = azurerm_api_management.main.id
}

output "name" {
  description = "Name of the API Management service"
  value       = azurerm_api_management.main.name
}

output "gateway_url" {
  description = "Gateway URL of the API Management service"
  value       = azurerm_api_management.main.gateway_url
}

output "management_api_url" {
  description = "Management API URL of the API Management service"
  value       = azurerm_api_management.main.management_api_url
}

output "portal_url" {
  description = "Portal URL of the API Management service"
  value       = azurerm_api_management.main.portal_url
}


