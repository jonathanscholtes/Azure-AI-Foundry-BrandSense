resource "azurerm_application_insights" "ai_foundry" {
  name                = var.app_insights_name
  location            = var.location
  resource_group_name = var.resource_group_name
  application_type    = "web"

  tags = merge(
    var.tags,
    {
      Name = var.app_insights_name
    }
  )
}
