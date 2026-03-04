output "id" {
  description = "ID of Application Insights"
  value       = azurerm_application_insights.ai_foundry.id
}

output "name" {
  description = "Name of Application Insights"
  value       = azurerm_application_insights.ai_foundry.name
}

output "instrumentation_key" {
  description = "Instrumentation key of Application Insights"
  value       = azurerm_application_insights.ai_foundry.instrumentation_key
  sensitive   = true
}

output "app_id" {
  description = "App ID of Application Insights"
  value       = azurerm_application_insights.ai_foundry.app_id
}
