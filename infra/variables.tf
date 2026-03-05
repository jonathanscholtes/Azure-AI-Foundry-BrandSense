variable "subscription_id" {
  description = "Azure Subscription ID"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-brnd"
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "eastus"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "resource_token" {
  description = "Resource token for unique naming"
  type        = string
  default     = "token"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "brnd"
}

# AI Foundry Variables
variable "ai_hub_name" {
  description = "Name of the AI Hub"
  type        = string
  default     = "aihub-foundry"
}

variable "ai_project_name" {
  description = "Name of the AI Project"
  type        = string
  default     = "aiproject-foundry"
}

# Managed Identity Variables
variable "managed_identity_name" {
  description = "Name of the user-assigned managed identity for all services"
  type        = string
  default     = "id-brnd-main"
}

# Application Insights Variables
variable "app_insights_name" {
  description = "Name of Application Insights"
  type        = string
  default     = "appi-brnd"
}

# AI Services Variables
variable "ai_services_deployment_gpt41_capacity" {
  description = "Capacity for GPT-4.1 deployment"
  type        = number
  default     = 150
}

variable "ai_services_deployment_embedding_capacity" {
  description = "Capacity for text-embedding-ada-002 deployment"
  type        = number
  default     = 100
}

# AI Search Variables
variable "search_service_name" {
  description = "Name of the AI Search service"
  type        = string
  default     = "search-brnd"
}

variable "search_sku" {
  description = "SKU for AI Search service"
  type        = string
  default     = "free"

  validation {
    condition     = contains(["free", "basic", "standard", "standard2", "standard3", "storage_optimized_l1", "storage_optimized_l2"], var.search_sku)
    error_message = "Search SKU must be a valid value."
  }
}

variable "semantic_search_sku" {
  description = "Semantic search tier for AI Search service (disabled, free, or standard)"
  type        = string
  default     = "free"

  validation {
    condition     = contains(["disabled", "free", "standard"], var.semantic_search_sku)
    error_message = "semantic_search_sku must be one of: disabled, free, standard."
  }
}

# API Management Variables
variable "apim_publisher_name" {
  description = "Publisher name for API Management"
  type        = string
  default     = "BrandSense"
}

variable "apim_publisher_email" {
  description = "Publisher email for API Management"
  type        = string
  default     = "admin@brandsense.com"
}

variable "apim_sku" {
  description = "SKU for API Management"
  type        = string
  default     = "Consumption"

  validation {
    condition     = contains(["Consumption", "Developer", "Basic", "Standard", "Premium"], var.apim_sku)
    error_message = "APIM SKU must be a valid value."
  }
}

variable "apim_sku_capacity" {
  description = "Capacity for API Management"
  type        = number
  default     = 1
}

# Storage Account Variables
variable "storage_account_name" {
  description = "Name of the storage account"
  type        = string
  default     = "stobrnd"
}

variable "storage_account_tier" {
  description = "Storage account tier"
  type        = string
  default     = "Standard"
}

variable "storage_replication_type" {
  description = "Storage account replication type"
  type        = string
  default     = "LRS"
}

# Key Vault Variables
variable "key_vault_name" {
  description = "Name of the Key Vault"
  type        = string
  default     = "kv-brnd"
}

variable "enable_purge_protection" {
  description = "Enable purge protection for Key Vault"
  type        = bool
  default     = false
}

# Container Registry Variables
variable "container_registry_name" {
  description = "Name of the Container Registry"
  type        = string
  default     = "acrbrnd"
}

variable "container_registry_sku" {
  description = "SKU for Container Registry"
  type        = string
  default     = "Basic"
}

# Container Apps Variables
variable "container_app_name" {
  description = "Name of the Container App hosting the BrandSense API"
  type        = string
  default     = "brnd-api"
}

variable "container_app_image" {
  description = "Container image to deploy. Defaults to a public placeholder used on first deploy; Phase 1.5 updates the app with the real ACR image."
  type        = string
  default     = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
}

variable "container_app_ui_name" {
  description = "Name of the Container App hosting the BrandSense UI"
  type        = string
  default     = "brnd-ui"
}

variable "container_app_ui_image" {
  description = "Container image for the UI. Defaults to a public placeholder used on first deploy; Phase 1.5 updates the app with the real ACR image."
  type        = string
  default     = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
}

# GitHub Actions service principal
variable "github_sp_object_id" {
  description = "Object ID of the GitHub Actions service principal. When set, grants the SP the same data-plane roles the deploying user receives (KV Secrets Officer, AI Project Management, AI User, Search Index Data Contributor)."
  type        = string
  default     = ""
}

# Tagging
variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Environment = "dev"
    Project     = "BrandSense"
    ManagedBy   = "Terraform"
  }
}
