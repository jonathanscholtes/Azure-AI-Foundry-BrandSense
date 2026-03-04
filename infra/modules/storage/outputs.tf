output "id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.main.id
}

output "name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.main.name
}

output "primary_blob_endpoint" {
  description = "The endpoint URL of the primary blob service"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "primary_queue_endpoint" {
  description = "The endpoint URL of the primary queue service"
  value       = azurerm_storage_account.main.primary_queue_endpoint
}

output "primary_table_endpoint" {
  description = "The endpoint URL of the primary table service"
  value       = azurerm_storage_account.main.primary_table_endpoint
}
