output "fqdn" {
  description = "Fully qualified domain name of the Container App"
  value       = azurerm_container_app.main.ingress[0].fqdn
}

output "url" {
  description = "HTTPS URL of the Container App"
  value       = "https://${azurerm_container_app.main.ingress[0].fqdn}"
}

output "name" {
  description = "Name of the Container App"
  value       = azurerm_container_app.main.name
}
