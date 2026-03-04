resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location

  tags = merge(
    var.tags,
    {
      Name = var.resource_group_name
    }
  )
}

data "azurerm_client_config" "current" {}
