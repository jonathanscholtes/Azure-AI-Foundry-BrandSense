terraform {
  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.0"
    }
  }
}



resource "azapi_resource" "ai_account" {
  type      = "Microsoft.CognitiveServices/accounts@2025-09-01"
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
}

resource "azapi_resource" "gpt41_deployment" {
  type      = "Microsoft.CognitiveServices/accounts/deployments@2025-09-01"
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
  type      = "Microsoft.CognitiveServices/accounts/deployments@2025-09-01"
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
  type      = "Microsoft.CognitiveServices/accounts/projects@2025-09-01"
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

# Register the AI Search service as a connection inside the Foundry project.
# This replaces the 'az ml connection create' approach (which targets ML workspaces,
# not Cognitive Services projects).
resource "azapi_resource" "search_connection" {
  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-09-01"
  name      = "brandsense-search"
  parent_id = azapi_resource.ai_project.id

  body = {
    properties = {
      category      = "CognitiveSearch"
      target        = "${var.search_service_endpoint}/"
      authType      = "AAD"
      isSharedToAll = true
      metadata = {
        ApiType    = "Azure"
        ResourceId = var.search_service_id
      }
    }
  }

  depends_on = [azapi_resource.ai_project]
}

# Register Application Insights as a connection inside the Foundry project.
resource "azapi_resource" "appinsights_connection" {
  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-09-01"
  name      = "brandsense-appinsights"
  parent_id = azapi_resource.ai_project.id

  body = {
    properties = {
      authType          = "ApiKey"
      category          = "AppInsights"
      target            = var.app_insights_id
      isSharedToAll     = true
      useWorkspaceManagedIdentity = false
      credentials = {
        key = var.app_insights_instrumentation_key
      }
      sharedUserList = []
      peRequirement  = "NotRequired"
      peStatus       = "NotApplicable"
      metadata = {
        ApiType    = "Azure"
        ResourceId = var.app_insights_id
      }
    }
  }

  depends_on = [azapi_resource.ai_project]
}

# Cognitive Services OpenAI User – allows inference calls
resource "azurerm_role_assignment" "openai_user" {
  scope                = azapi_resource.ai_account.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = var.identity_principal_id

  depends_on = [azapi_resource.ai_account]
}

# Cognitive Services OpenAI Contributor – needed to manage deployments/agents
resource "azurerm_role_assignment" "openai_contributor" {
  scope            = azapi_resource.ai_account.id
  role_definition_id = "/subscriptions/${var.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/a001fd3d-188f-4b5d-821b-7da978bf7442"
  principal_id     = var.identity_principal_id

  depends_on = [azapi_resource.ai_account]
}

# Cognitive Services User – general data-plane access
resource "azurerm_role_assignment" "cognitive_services_user" {
  scope                = azapi_resource.ai_account.id
  role_definition_name = "Cognitive Services User"
  principal_id         = var.identity_principal_id

  depends_on = [azapi_resource.ai_account]
}

# AI User – required for Foundry agent invoke/read operations
resource "azurerm_role_assignment" "ai_user" {
  scope            = azapi_resource.ai_account.id
  role_definition_id = "/subscriptions/${var.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/53ca6127-db72-4b80-b1b0-d745d6d5456d"
  principal_id     = var.identity_principal_id

  depends_on = [azapi_resource.ai_account]
}

# AI Project Management – required to create/manage agents in the Foundry project
resource "azurerm_role_assignment" "ai_project_management" {
  scope            = azapi_resource.ai_account.id
  role_definition_id = "/subscriptions/${var.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/eadc314b-1a2d-4efa-be10-5d325db5065e"
  principal_id     = var.identity_principal_id

  depends_on = [azapi_resource.ai_account]
}
