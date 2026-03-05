output "ai_account_id" {
  description = "ID of the AI Services account"
  value       = azapi_resource.ai_account.id
}

output "ai_account_endpoint" {
  description = "Endpoint of the AI Services account"
  value       = azapi_resource.ai_account.output.properties.endpoint
}

output "ai_account_name" {
  description = "Name of the AI Services account"
  value       = var.ai_account_name
}

output "openai_endpoint" {
  description = "OpenAI endpoint for the AI Services account"
  value       = "https://${var.ai_account_name}.cognitiveservices.azure.com/"
}

output "ai_project_id" {
  description = "ID of the AI Project"
  value       = azapi_resource.ai_project.id
}

output "ai_project_name" {
  description = "Name of the AI Project"
  value       = var.ai_project_name
}

output "ai_project_endpoint" {
  description = "Endpoint URL for the AI Foundry project (azure-ai-projects SDK)"
  value       = "https://${var.ai_account_name}.cognitiveservices.azure.com/api/projects/${var.ai_project_name}/"
}

output "ai_project_principal_id" {
  description = "System-assigned managed identity principal ID of the AI Foundry project (used to grant Search access)"
  value       = azapi_resource.ai_project.identity[0].principal_id
}
