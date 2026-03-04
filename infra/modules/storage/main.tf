resource "azurerm_storage_account" "main" {
  name                     = replace(var.storage_account_name, "-", "")
  location                 = var.location
  resource_group_name      = var.resource_group_name
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  account_kind             = "StorageV2"

  is_hns_enabled = false
  shared_access_key_enabled = false

  tags = merge(
    var.tags,
    {
      Name = var.storage_account_name
    }
  )
}

resource "azurerm_storage_container" "containers" {
  for_each = toset(var.storage_containers)

  name                  = each.key
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

resource "azurerm_role_assignment" "blob_contributor" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.identity_principal_id

  depends_on = [azurerm_storage_account.main]
}

resource "azurerm_role_assignment" "table_contributor" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = var.identity_principal_id

  depends_on = [azurerm_storage_account.main]
}

resource "azurerm_role_assignment" "account_contributor" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Account Contributor"
  principal_id         = var.identity_principal_id

  depends_on = [azurerm_storage_account.main]
}

resource "azurerm_role_assignment" "blob_owner" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = var.identity_principal_id

  depends_on = [azurerm_storage_account.main]
}

resource "azurerm_role_assignment" "queue_contributor" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = var.identity_principal_id

  depends_on = [azurerm_storage_account.main]
}
