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

output "halo_mcp_api_id" {
  description = "ID of the Halo MCP API"
  value       = azapi_resource.halo_mcp.id
}

output "halo_http_api_id" {
  description = "ID of the Halo HTTP API"
  value       = length(azurerm_api_management_api.halo_http) > 0 ? azurerm_api_management_api.halo_http[0].id : null
}

output "kb_tag_id" {
  description = "ID of the KB tag"
  value       = azurerm_api_management_tag.kb.id
}
