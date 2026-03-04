resource "azurerm_api_management" "main" {
  name                = var.apim_name
  location            = var.location
  resource_group_name = var.resource_group_name
  publisher_name      = var.publisher_name
  publisher_email     = var.publisher_email
  sku_name            = var.apim_sku == "Consumption" ? "Consumption" : "${var.apim_sku}_${var.apim_sku_capacity}"
  client_certificate_enabled = false

  identity {
    type         = "SystemAssigned, UserAssigned"
    identity_ids = [var.managed_identity_id]
  }

  tags = merge(
    var.tags,
    {
      Name = var.apim_name
    }
  )

  timeouts {
    create = "120m"
    delete = "60m"
    update = "120m"
  }
}

# ================================================
# BrandSense API
# ================================================

resource "azurerm_api_management_api" "brandsense" {
  name                  = "brandsense-api"
  resource_group_name   = var.resource_group_name
  api_management_name   = azurerm_api_management.main.name
  revision              = "1"
  display_name          = "BrandSense API"
  description           = "BrandSense brand validation and asset analysis API"
  service_url           = var.container_app_url
  path                  = "brandsense"
  protocols             = ["https"]
  subscription_required = false

  depends_on = [azurerm_api_management.main]
}

# GET /health
resource "azurerm_api_management_api_operation" "health" {
  operation_id        = "health-check"
  api_name            = azurerm_api_management_api.brandsense.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = var.resource_group_name
  display_name        = "Health Check"
  method              = "GET"
  url_template        = "/health"
}

# POST /validate
resource "azurerm_api_management_api_operation" "validate" {
  operation_id        = "validate-brand"
  api_name            = azurerm_api_management_api.brandsense.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = var.resource_group_name
  display_name        = "Validate Brand Assets"
  method              = "POST"
  url_template        = "/validate"
}

# POST /tools/extract-fonts
resource "azurerm_api_management_api_operation" "extract_fonts" {
  operation_id        = "extract-fonts"
  api_name            = azurerm_api_management_api.brandsense.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = var.resource_group_name
  display_name        = "Extract Fonts"
  method              = "POST"
  url_template        = "/tools/extract-fonts"
}
