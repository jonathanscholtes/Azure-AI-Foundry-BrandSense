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
  description         = "Returns service liveness status. Use to confirm the BrandSense API is reachable before submitting a validation job."

  response {
    status_code = 200
    description = "Service is healthy"
  }
}

# POST /validate
resource "azurerm_api_management_api_operation" "validate" {
  operation_id        = "validate-brand"
  api_name            = azurerm_api_management_api.brandsense.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = var.resource_group_name
  display_name        = "Validate Brand Asset"
  method              = "POST"
  url_template        = "/validate"
  description         = "Submits a PDF marketing asset for full brand, legal, and SEO compliance validation. The pipeline runs three Foundry agents (Researcher, Auditor, Briefer) and returns a structured audit report with pass/fail checks, error counts, and a creative brief. Accepts multipart/form-data with a single 'file' field (PDF, max 50 MB)."

  request {
    description = "PDF marketing asset to validate"
    representation {
      content_type = "multipart/form-data"
    }
  }

  response {
    status_code = 200
    description = "Validation complete — returns audit checks, summary counts, and creative brief"
    representation {
      content_type = "application/json"
    }
  }

  response {
    status_code = 422
    description = "Validation error — file missing, wrong type, or exceeds size limit"
  }
}

# POST /tools/extract-fonts
resource "azurerm_api_management_api_operation" "extract_fonts" {
  operation_id        = "extract-fonts"
  api_name            = azurerm_api_management_api.brandsense.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = var.resource_group_name
  display_name        = "Extract Fonts and Colours"
  method              = "POST"
  url_template        = "/tools/extract-fonts"
  description         = "MCP tool: brandsense.extract_fonts() — extracts all font families, sizes, weights, and colour hex values used in a PDF document. Call this before evaluating any brand typography or colour compliance checks. Accepts multipart/form-data with a single 'file' field (PDF). Returns a JSON object with 'fonts' (list of font descriptors) and 'colors' (list of hex strings) found in the document."

  request {
    description = "PDF document to inspect for font and colour usage"
    representation {
      content_type = "multipart/form-data"
    }
  }

  response {
    status_code = 200
    description = "Extraction successful — returns fonts and colors arrays"
    representation {
      content_type = "application/json"
    }
  }
}

# ================================================
# BrandSense Product
# ================================================

# Groups all BrandSense APIs under a single product so that:
#  - rate limiting / quota policies can be applied at product scope
#  - access tiers (UI vs agent) can be managed via separate subscriptions
#  - subscription_required is off by default (matching the API) and can
#    be enabled once the UI and MCP agent are wired to forward the key
resource "azurerm_api_management_product" "brandsense" {
  product_id            = "brandsense"
  resource_group_name   = var.resource_group_name
  api_management_name   = azurerm_api_management.main.name
  display_name          = "BrandSense Services"
  description           = "Access to BrandSense brand validation, asset analysis, and MCP agent endpoints"
  subscription_required = false
  approval_required     = false
  published             = true

  depends_on = [azurerm_api_management.main]
}

# Associate the BrandSense API with the product
resource "azurerm_api_management_product_api" "brandsense" {
  resource_group_name = var.resource_group_name
  api_management_name = azurerm_api_management.main.name
  product_id          = azurerm_api_management_product.brandsense.product_id
  api_name            = azurerm_api_management_api.brandsense.name
}
