resource "azurerm_container_registry" "main" {
  name                = replace(var.container_registry_name, "-", "")
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.container_registry_sku
  admin_enabled       = true

  tags = merge(
    var.tags,
    {
      Name = var.container_registry_name
    }
  )
}
