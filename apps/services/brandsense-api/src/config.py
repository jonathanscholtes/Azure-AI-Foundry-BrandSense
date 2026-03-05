"""BrandSense API — configuration.

Pydantic settings loaded from environment variables (or .env in local dev).
All secrets are injected via Container Apps environment variables / Key Vault references.
"""

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # Application
    environment: str = Field(default="dev", description="Deployment environment (dev, prod)")
    log_level: str = Field(default="INFO")
    port: int = Field(default=80)

    # Azure identity (injected by Container App managed identity)
    azure_client_id: str = Field(default="", description="Client ID of the User Assigned Managed Identity")

    # Microsoft Foundry
    foundry_project_connection_string: str = Field(
        default="",
        description="Azure AI Foundry project endpoint URL",
    )

    # Foundry Agent IDs (written to Key Vault by deploy_foundry_agents.py,
    # injected as env vars via Container Apps Key Vault references)
    researcher_agent_id: str = Field(default="", description="Foundry agent ID for the Marketing Researcher")
    auditor_agent_id: str = Field(default="", description="Foundry agent ID for the Marketing Auditor")
    briefer_agent_id: str = Field(default="", description="Foundry agent ID for the Marketing Briefer")

    # Azure OpenAI
    azure_openai_endpoint: str = Field(default="")
    azure_openai_deployment_gpt41: str = Field(default="gpt-4.1")
    azure_openai_deployment_gpt41_vision: str = Field(default="gpt-4.1")

    # Azure AI Search
    azure_search_endpoint: str = Field(default="")
    azure_search_index_name: str = Field(default="brandsense-guidelines")

    # Azure AI Document Intelligence
    azure_document_intelligence_endpoint: str = Field(default="")

    # Azure Blob Storage
    azure_storage_account_name: str = Field(default="stobrandsense")
    azure_storage_container_assets: str = Field(default="assets-raw")

    # APIM MCP Server endpoint — configured in the Foundry Auditor agent
    apim_mcp_endpoint: str = Field(default="")


settings = Settings()
