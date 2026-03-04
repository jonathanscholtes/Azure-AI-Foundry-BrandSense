"""
Deploy BrandSense Foundry Agents.

Creates or updates the three BrandSense agents in the Microsoft Foundry project
and writes their IDs to Azure Key Vault so the brandsense-api can discover them.

Agents are defined as individual modules under the ``agents`` package:
  - agents.researcher  : queries the brandsense-guidelines AI Search index
  - agents.auditor     : analyses the PDF asset against retrieved guidelines
                         (APIM MCP tool for PyMuPDF is added manually in the portal)
  - agents.briefer     : synthesises audit results into a creative brief

Usage:
    python agents/deploy.py \\
        --project-endpoint <FOUNDRY_PROJECT_ENDPOINT> \\
        --model-deployment gpt-4.1 \\
        --key-vault-name   <KEY_VAULT_NAME> \\
        [--search-connection-name brandsense-search]

    The script resolves the AI Search connection by name via the Foundry SDK.
    If not found by name it auto-discovers the first AI Search connection in
    the project; if none exists it deploys agents without the search tool.
"""

import argparse
import logging
import os
import sys
from typing import Optional

# When run as a script (python agents/deploy.py) the repo root is not
# automatically on sys.path, so the 'agents' package import below would fail.
# Insert the repo root explicitly.
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import (
    AISearchIndexResource,
    AzureAISearchAgentTool,
    AzureAISearchToolResource,
    PromptAgentDefinition,
)
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient

from agents import researcher, auditor, briefer

logging.basicConfig(level=logging.INFO, format="[%(levelname)s] %(message)s")
logger = logging.getLogger(__name__)

# Map of short name -> module (used by --only filter)
AGENT_MODULE_MAP = {
    "researcher": researcher,
    "auditor":    auditor,
    "briefer":    briefer,
}

# Ordered list of agent modules to deploy (all agents)
AGENT_MODULES = list(AGENT_MODULE_MAP.values())

# Default Foundry connection name created by Terraform
DEFAULT_SEARCH_CONNECTION_NAME = "brandsense-search"


# ---------------------------------------------------------------------------
# Deployer
# ---------------------------------------------------------------------------

class AgentDeployer:
    """Create or update BrandSense agents in Microsoft Foundry."""

    def __init__(
        self,
        project_endpoint: str,
        model_deployment: str,
        key_vault_name: str,
        search_connection_name: Optional[str],
    ):
        self.project_endpoint       = project_endpoint
        self.model_deployment       = model_deployment
        self.key_vault_name         = key_vault_name
        self.search_connection_name = search_connection_name
        self.search_connection_id: Optional[str] = None  # resolved at deploy time

        credential = DefaultAzureCredential()

        self.project_client = AIProjectClient(
            endpoint=project_endpoint,
            credential=credential,
        )

        self.kv_client = SecretClient(
            vault_url=f"https://{key_vault_name}.vault.azure.net",
            credential=credential,
        )

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _resolve_search_connection_id(self) -> Optional[str]:
        """Resolve AI Search connection ID from its name via the Foundry SDK.

        Resolution order:
        1. Named lookup using self.search_connection_name.
        2. Auto-discover: first AI Search connection listed in the project.
        3. Return None (agents deploy without the search tool).
        """
        if self.search_connection_name:
            try:
                conn = self.project_client.connections.get(self.search_connection_name)
                logger.info("AI Search connection resolved: %s -> %s", conn.name, conn.id)
                return conn.id
            except Exception:
                logger.warning(
                    "Connection '%s' not found - attempting auto-discover.",
                    self.search_connection_name,
                )

        try:
            for conn in self.project_client.connections.list():
                conn_type = getattr(conn, "connection_type", "") or ""
                if "search" in conn_type.lower():
                    logger.info(
                        "Auto-discovered AI Search connection: %s -> %s",
                        conn.name, conn.id,
                    )
                    return conn.id
        except Exception as exc:
            logger.warning("Could not list project connections: %s", exc)

        logger.warning(
            "No AI Search connection found in the Foundry project. "
            "Researcher and Auditor will be deployed WITHOUT the AI Search tool. "
            "Create the connection in the Foundry portal then re-run."
        )
        return None

    def _search_tools(self) -> list:
        if not self.search_connection_id:
            return []
        return [
            AzureAISearchAgentTool(
                azure_ai_search=AzureAISearchToolResource(
                    indexes=[
                        AISearchIndexResource(
                            project_connection_id=self.search_connection_id,
                            index_name="brandsense-guidelines",
                        )
                    ]
                )
            )
        ]

    def _create_or_update(self, agent_name: str, instructions: str, tools: list) -> str:
        """Create or update a named agent and return its ID."""
        definition = PromptAgentDefinition(
            model=self.model_deployment,
            instructions=instructions,
            tools=tools or None,
        )

        existing = None
        try:
            existing = self.project_client.agents.get(agent_name)
        except Exception:
            pass  # agent does not exist yet

        if existing:
            agent = self.project_client.agents.update(
                agent_name=agent_name,
                definition=definition,
            )
            logger.info("Updated  %-35s id=%s", agent_name, agent.id)
        else:
            agent = self.project_client.agents.create_version(
                agent_name=agent_name,
                definition=definition,
            )
            logger.info("Created  %-35s id=%s", agent_name, agent.id)

        return agent.id

    def _write_kv_secret(self, secret_name: str, value: str) -> None:
        self.kv_client.set_secret(secret_name, value)
        logger.info("Key Vault secret set: %s", secret_name)

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def deploy(self, only: Optional[list] = None) -> dict:
        """Deploy agents.

        Args:
            only: If provided, a list of short agent names (e.g. ["researcher"])
                  to deploy.  When *None* or empty, all agents are deployed.
        """
        if only:
            modules = [AGENT_MODULE_MAP[n] for n in only if n in AGENT_MODULE_MAP]
            if not modules:
                logger.error(
                    "None of the requested agents matched: %s  (valid: %s)",
                    only, list(AGENT_MODULE_MAP.keys()),
                )
                sys.exit(1)
        else:
            modules = AGENT_MODULES

        label = ", ".join(m.NAME for m in modules)
        logger.info("=" * 60)
        logger.info("BrandSense - deploying Foundry agents")
        logger.info("  Project    : %s", self.project_endpoint)
        logger.info("  Model      : %s", self.model_deployment)
        logger.info("  KV         : %s", self.key_vault_name)
        logger.info("  Search conn: %s", self.search_connection_name or "(auto-discover)")
        logger.info("  Agents     : %s", label)
        logger.info("=" * 60)

        # Resolve AI Search connection ID from name (or auto-discover)
        self.search_connection_id = self._resolve_search_connection_id()
        search_tools = self._search_tools()
        results = {}

        try:
            for agent_mod in modules:
                tools = search_tools if agent_mod.USES_SEARCH else []
                agent_id = self._create_or_update(
                    agent_mod.NAME,
                    agent_mod.INSTRUCTIONS,
                    tools,
                )
                results[agent_mod.NAME] = agent_id
                self._write_kv_secret(agent_mod.KV_SECRET, agent_id)

            logger.info("=" * 60)
            logger.info("[OK] Agents deployed.")
            for name, aid in results.items():
                logger.info("  %-35s : %s", name, aid)
            logger.info("=" * 60)
            return results

        except Exception:
            logger.exception("Agent deployment failed.")
            sys.exit(1)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Deploy BrandSense Foundry agents and write IDs to Key Vault."
    )
    parser.add_argument("--project-endpoint",  required=True)
    parser.add_argument("--model-deployment",  default="gpt-4.1")
    parser.add_argument("--key-vault-name",    required=True)
    parser.add_argument(
        "--search-connection-name",
        default=DEFAULT_SEARCH_CONNECTION_NAME,
        help="Name of the AI Search connection registered in the Foundry project. "
             "Resolved to a resource ID via the SDK. "
             "Defaults to 'brandsense-search'. "
             "If not found, auto-discovers the first AI Search connection.",
    )
    parser.add_argument(
        "--only",
        nargs="+",
        choices=list(AGENT_MODULE_MAP.keys()),
        default=None,
        help="Deploy only the specified agent(s).  "
             "Omit to deploy all agents.",
    )
    args = parser.parse_args()

    deployer = AgentDeployer(
        project_endpoint=args.project_endpoint,
        model_deployment=args.model_deployment,
        key_vault_name=args.key_vault_name,
        search_connection_name=args.search_connection_name,
    )
    deployer.deploy(only=args.only)


if __name__ == "__main__":
    main()
