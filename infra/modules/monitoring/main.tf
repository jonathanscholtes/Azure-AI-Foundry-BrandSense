resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-${replace(var.app_insights_name, "appi-", "")}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = merge(
    var.tags,
    {
      Name = "law-${replace(var.app_insights_name, "appi-", "")}"
    }
  )
}

resource "azurerm_application_insights" "ai_foundry" {
  name                = var.app_insights_name
  location            = var.location
  resource_group_name = var.resource_group_name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"

  tags = merge(
    var.tags,
    {
      Name = var.app_insights_name
    }
  )
}
