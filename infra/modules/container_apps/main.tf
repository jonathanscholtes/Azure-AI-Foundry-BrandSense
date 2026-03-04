resource "azurerm_container_app" "main" {
  name                         = var.container_app_name
  container_app_environment_id = var.container_app_environment_id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [var.managed_identity_id]
  }

  registry {
    server   = var.container_registry_server
    identity = var.managed_identity_id
  }

  template {
    container {
      name   = var.container_app_name
      image  = var.container_app_image
      cpu    = 1.0
      memory = "2Gi"

      env {
        name  = "AZURE_CLIENT_ID"
        value = var.managed_identity_client_id
      }

      dynamic "env" {
        for_each = var.extra_env_vars
        content {
          name  = env.key
          value = env.value
        }
      }
    }

    min_replicas = 1
    max_replicas = 3
  }

  ingress {
    external_enabled = true
    target_port      = 80

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  tags = var.tags

  # The image is bootstrapped with a public placeholder on first deploy.
  # Phase 1.5 of deploy.ps1 builds the real ACR image and updates the app
  # via 'az containerapp update', so Terraform must not revert template changes.
  lifecycle {
    ignore_changes = [template]
  }
}
