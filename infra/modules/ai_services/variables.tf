variable "ai_account_name" {
  description = "Name of the AI Services account"
  type        = string
}

variable "ai_project_name" {
  description = "Name of the AI Project"
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

variable "subscription_id" {
  description = "Azure Subscription ID"
  type        = string
}

variable "identity_id" {
  description = "ID of the managed identity"
  type        = string
}

variable "identity_principal_id" {
  description = "Principal ID of the managed identity"
  type        = string
}

variable "gpt41_capacity" {
  description = "Capacity for GPT-4.1 deployment"
  type        = number
  default     = 150
}

variable "embedding_capacity" {
  description = "Capacity for text-embedding-ada-002 deployment"
  type        = number
  default     = 120
}
