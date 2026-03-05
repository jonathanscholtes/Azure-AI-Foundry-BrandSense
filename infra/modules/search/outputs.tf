output "id" {
  description = "ID of the AI Search service"
  value       = azurerm_search_service.main.id
}

output "name" {
  description = "Name of the AI Search service"
  value       = azurerm_search_service.main.name
}

output "endpoint" {
  description = "Endpoint of the AI Search service"
  value       = "https://${azurerm_search_service.main.name}.search.windows.net"
}

output "principal_id" {
  description = "System-assigned managed identity principal ID of the search service (used for integrated vectorizer RBAC)"
  value       = try(azurerm_search_service.main.identity[0].principal_id, null)
}
