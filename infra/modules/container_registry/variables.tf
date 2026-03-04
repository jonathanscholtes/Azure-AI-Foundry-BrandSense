variable "container_registry_name" {
  description = "Name of the Container Registry"
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

variable "container_registry_sku" {
  description = "SKU for Container Registry"
  type        = string
  default     = "Basic"
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}
