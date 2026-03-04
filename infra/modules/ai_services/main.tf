terraform {
  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.0"
    }
  }
}



resource "azapi_resource" "ai_account" {
  type      = "Microsoft.CognitiveServices/accounts@2025-06-01"
  name      = var.ai_account_name
  location  = var.location
  parent_id = "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}"

  identity {
    type         = "UserAssigned"
    identity_ids = [var.identity_id]
  }

  body = {
    kind = "AIServices"
    properties = {
      apiProperties      = {}
      customSubDomainName = var.ai_account_name
      networkAcls = {
        defaultAction         = "Allow"
        virtualNetworkRules   = []
        ipRules               = []
      }
      allowProjectManagement = true
      publicNetworkAccess    = "Enabled"
      disableLocalAuth       = false
    }
    sku = {
      name = "S0"
    }
    tags = {
      "SecurityControl" = "ignore"
    }
  }

  depends_on = []
}

resource "azapi_resource" "gpt41_deployment" {
  type      = "Microsoft.CognitiveServices/accounts/deployments@2025-06-01"
  name      = "gpt-4.1"
  parent_id = azapi_resource.ai_account.id

  body = {
    sku = {
      name     = "Standard"
      capacity = var.gpt41_capacity
    }
    properties = {
      model = {
        format  = "OpenAI"
        name    = "gpt-4.1"
        version = "2025-04-14"
      }
      versionUpgradeOption = "OnceNewDefaultVersionAvailable"
    }
  }

  depends_on = [azapi_resource.ai_account]
}

resource "azapi_resource" "embedding_deployment" {
  type      = "Microsoft.CognitiveServices/accounts/deployments@2025-06-01"
  name      = "text-embedding-ada-002"
  parent_id = azapi_resource.ai_account.id

  body = {
    sku = {
      name     = "Standard"
      capacity = var.embedding_capacity
    }
    properties = {
      model = {
        format  = "OpenAI"
        name    = "text-embedding-ada-002"
        version = "2"
      }
      versionUpgradeOption = "OnceNewDefaultVersionAvailable"
    }
  }

  depends_on = [azapi_resource.gpt41_deployment]
}

resource "azapi_resource" "ai_project" {
  type      = "Microsoft.CognitiveServices/accounts/projects@2025-06-01"
  name      = var.ai_project_name
  location  = var.location
  parent_id = azapi_resource.ai_account.id

  identity {
    type = "SystemAssigned"
  }

  body = {
    properties = {}
  }

  depends_on = [
    azapi_resource.ai_account,
    azapi_resource.gpt41_deployment,
    azapi_resource.embedding_deployment
  ]
}

resource "azurerm_role_assignment" "openai_user" {
  scope                = azapi_resource.ai_account.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = var.identity_principal_id

  depends_on = [azapi_resource.ai_account]
}

resource "azurerm_role_assignment" "cognitive_services_user" {
  scope                = azapi_resource.ai_account.id
  role_definition_name = "Cognitive Services User"
  principal_id         = var.identity_principal_id

  depends_on = [azapi_resource.ai_account]
}
