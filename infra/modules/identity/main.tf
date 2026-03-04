resource "azurerm_user_assigned_identity" "main" {
  name                = var.managed_identity_name
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = merge(
    var.tags,
    {
      Name = var.managed_identity_name
    }
  )
}
