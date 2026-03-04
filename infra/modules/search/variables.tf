variable "search_service_name" {
  description = "Name of the AI Search service"
  type        = string
}

variable "location" {
  description = "Azure region for resources"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
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

variable "identity_principal_id" {
  description = "Principal ID of the managed identity"
  type        = string
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}
