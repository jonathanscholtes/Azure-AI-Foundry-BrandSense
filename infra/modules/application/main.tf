

# Backend Container App Environment
resource "azurerm_container_app_environment" "backend" {
  name                = "cae-${var.project_name}-${var.environment_name}-${var.resource_token}"
  location            = var.location
  resource_group_name = var.resource_group_name
  log_analytics_workspace_id = data.azurerm_log_analytics_workspace.main.id
}



# FastAPI Backend Container App
resource "azurerm_container_app" "backend" {
  name                = "backend-${var.project_name}-${var.environment_name}-${var.resource_token}"
  container_app_environment_id = azurerm_container_app_environment.backend.id
  resource_group_name = var.resource_group_name

  identity {
    type         = "UserAssigned"
    identity_ids = [var.managed_identity_id]
  }

  revision_mode = "Single"

  template {
    container {
      name   = "service-desk-backend"
      image  = "${var.container_registry_login_server}/service-desk-backend:latest"
      cpu    = 0.5
      memory = "1.0Gi"
      env {
        name  = "SERVICE_NAME"
        value = "service-desk"
      }
      env {
        name  = "PORT"
        value = "80"
      }
      env {
        name  = "AZURE_CLIENT_ID"
        value = data.azurerm_user_assigned_identity.main.client_id
      }
    }
  }

  ingress {
    external_enabled = true
    target_port      = 80
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }


  registry {
    server   = var.container_registry_login_server
    identity = var.managed_identity_id
  }
}


# Frontend Web App
resource "azurerm_linux_web_app" "frontend" {
  name                = local.frontend_web_app_name
  location            = var.location
  resource_group_name = var.resource_group_name
  service_plan_id     = data.azurerm_service_plan.main.id

  identity {
    type         = "UserAssigned"
    identity_ids = [var.managed_identity_id]
  }

  site_config {
    always_on = true
    application_stack {
      node_version = "20-lts"
    }
    app_command_line = "pm2 serve /home/site/wwwroot --spa --no-daemon"
  }

  app_settings = {
    SCM_DO_BUILD_DURING_DEPLOYMENT = "0"
    REACT_APP_API_HOST             = "https://${local.backend_web_app_name}.azurewebsites.net"
    APPINSIGHTS_INSTRUMENTATIONKEY = data.azurerm_application_insights.main.instrumentation_key
  }

  public_network_access_enabled = true
}

# Frontend Diagnostic Settings
resource "azurerm_monitor_diagnostic_setting" "frontend" {
  name                       = "${local.frontend_web_app_name}-diagnostic"
  target_resource_id         = azurerm_linux_web_app.frontend.id
  log_analytics_workspace_id = data.azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "AppServiceHTTPLogs"
  }
  enabled_log {
    category = "AppServiceConsoleLogs"
  }
  enabled_log {
    category = "AppServiceAppLogs"
  }

  metric {
    category = "AllMetrics"
  }
}