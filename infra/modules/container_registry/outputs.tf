output "id" {
  description = "ID of the container registry"
  value       = azurerm_container_registry.main.id
}

output "name" {
  description = "Name of the container registry"
  value       = azurerm_container_registry.main.name
}

output "login_server" {
  description = "Login server of the container registry"
  value       = azurerm_container_registry.main.login_server
}
