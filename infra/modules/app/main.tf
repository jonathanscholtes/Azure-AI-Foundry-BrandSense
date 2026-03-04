variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment_name" {
  description = "Environment name"
  type        = string
}

variable "resource_token" {
  description = "Resource token"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

locals {
  app_service_plan_name = "asp-lnx-${var.project_name}-${var.environment_name}-${var.resource_token}"
}

# App Service Plan (Linux)
resource "azurerm_service_plan" "main" {
  name                = local.app_service_plan_name
  location            = var.location
  resource_group_name = var.resource_group_name
  os_type             = "Linux"
  sku_name            = "P1v3"
}

output "app_service_plan_name" {
  value = azurerm_service_plan.main.name
}

output "app_service_plan_id" {
  value = azurerm_service_plan.main.id
}
