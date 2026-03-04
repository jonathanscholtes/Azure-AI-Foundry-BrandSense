variable "apim_name" {
  description = "Name of API Management service"
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

variable "publisher_name" {
  description = "Publisher name for API Management"
  type        = string
  default     = "API Publisher"
}

variable "publisher_email" {
  description = "Publisher email for API Management"
  type        = string
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
  description = "Capacity for API Management (not used for Consumption)"
  type        = number
  default     = 1
}

variable "managed_identity_id" {
  description = "ID of the user-assigned managed identity for APIM to use when accessing Key Vault"
  type        = string
}

variable "key_vault_secret_identifier" {
  description = "Key Vault secret identifier URI for halo-api-key (only set after secret is pushed)"
  type        = string
  default     = null
}

variable "identity_client_id" {
  description = "Client ID of the managed identity for accessing Key Vault secrets in APIM (only set after secret is pushed)"
  type        = string
  default     = null
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}
