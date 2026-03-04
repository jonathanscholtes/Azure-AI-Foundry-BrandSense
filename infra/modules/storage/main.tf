terraform {
  required_providers {
    azapi = {
      source = "Azure/azapi"
    }
  }
}

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

# Use azapi_resource instead of azurerm_storage_container because the
# azurerm provider's container resource uses the Blob data-plane API, which
# requires Storage Blob Data Contributor.  That creates a chicken-and-egg
# during the first apply: the role assignment hasn't propagated yet when
# Terraform tries to refresh container state.  The azapi provider talks to
# the ARM management plane, which only needs the standard Contributor role.
resource "azapi_resource" "containers" {
  for_each = toset(var.storage_containers)

  type      = "Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01"
  name      = each.key
  parent_id = "${azurerm_storage_account.main.id}/blobServices/default"

  body = {
    properties = {
      publicAccess = "None"
    }
  }
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
