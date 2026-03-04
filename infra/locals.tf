locals {
  # Naming convention
  name_prefix = "${var.project_name}-${var.environment}"

  # AI Foundry naming
  ai_account_name = "fnd-${var.project_name}-${var.environment}-${var.resource_token}"
  ai_project_name = "proj-${var.project_name}-${var.environment}-${var.resource_token}"

  # Common tags for all resources
  common_tags = merge(
    var.tags,
    {
      "CreatedBy"  = "Terraform"
      "CreatedAt"  = timestamp()
      "Environment" = var.environment
      "Project"    = var.project_name
    }
  )
}
