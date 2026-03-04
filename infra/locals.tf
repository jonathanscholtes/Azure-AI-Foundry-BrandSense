locals {
  # Naming convention
  name_prefix = "${var.project_name}-${var.environment}"

  # AI Foundry naming
  ai_account_name = "fnd-${var.project_name}-${var.environment}-${var.resource_token}"
  ai_project_name = "proj-${var.project_name}-${var.environment}-${var.resource_token}"

  # Common tags for all resources
  # var.tags already contains Environment, Project, and ManagedBy from tfvars.
  common_tags = var.tags
}
