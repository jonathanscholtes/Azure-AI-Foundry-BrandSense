variable "container_app_name" {
  description = "Name of the Container App"
  type        = string
}

variable "container_app_image" {
  description = "Container image URI (e.g. acrbrnd.azurecr.io/brnd-api:latest)"
  type        = string
}

variable "container_app_environment_id" {
  description = "Resource ID of the shared Container Apps Environment"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "managed_identity_id" {
  description = "Resource ID of the user-assigned managed identity"
  type        = string
}

variable "managed_identity_client_id" {
  description = "Client ID of the user-assigned managed identity (injected as AZURE_CLIENT_ID env var)"
  type        = string
}

variable "container_registry_server" {
  description = "Login server of the Azure Container Registry"
  type        = string
}

variable "extra_env_vars" {
  description = "Additional environment variables to inject into the container (key = name, value = value)"
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
