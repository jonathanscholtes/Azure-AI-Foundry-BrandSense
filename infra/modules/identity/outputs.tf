output "id" {
  description = "ID of the managed identity"
  value       = azurerm_user_assigned_identity.main.id
}

output "principal_id" {
  description = "Principal ID of the managed identity"
  value       = azurerm_user_assigned_identity.main.principal_id
}

output "client_id" {
  description = "Client ID of the managed identity"
  value       = azurerm_user_assigned_identity.main.client_id
}

output "name" {
  description = "Name of the managed identity"
  value       = azurerm_user_assigned_identity.main.name
}
