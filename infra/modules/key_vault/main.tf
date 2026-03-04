resource "azurerm_key_vault" "main" {
  name                = replace(var.key_vault_name, "-", "")
  location            = var.location
  resource_group_name = var.resource_group_name
  tenant_id           = var.tenant_id
  sku_name            = "standard"
  enable_rbac_authorization       = true
  purge_protection_enabled   = var.enable_purge_protection
  soft_delete_retention_days = 7

  tags = merge(
    var.tags,
    {
      Name = var.key_vault_name
    }
  )
}

resource "azurerm_role_assignment" "keyvault_secrets_user" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = var.identity_principal_id

  depends_on = [azurerm_key_vault.main]
}

resource "azurerm_role_assignment" "keyvault_crypto_user" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Crypto User"
  principal_id         = var.identity_principal_id

  depends_on = [azurerm_key_vault.main]
}
