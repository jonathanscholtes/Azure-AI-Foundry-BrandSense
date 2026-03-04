resource "azurerm_search_service" "main" {
  name                = var.search_service_name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.search_sku

  tags = merge(
    var.tags,
    {
      Name = var.search_service_name
    }
  )

  depends_on = []
}

resource "azurerm_role_assignment" "search_service_contributor" {
  scope                = azurerm_search_service.main.id
  role_definition_name = "Search Service Contributor"
  principal_id         = var.identity_principal_id

  depends_on = [azurerm_search_service.main]
}

resource "azurerm_role_assignment" "search_index_data_contributor" {
  scope                = azurerm_search_service.main.id
  role_definition_name = "Search Index Data Contributor"
  principal_id         = var.identity_principal_id

  depends_on = [azurerm_search_service.main]
}
