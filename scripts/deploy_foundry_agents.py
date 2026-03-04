"""
Deploy BrandSense Foundry Agents.

Creates or updates the three BrandSense agents in the Microsoft Foundry project
and writes their IDs to Azure Key Vault so the brandsense-api can discover them.

Agents:
  - brandsense-researcher  : queries the brandsense-guidelines AI Search index
  - brandsense-auditor     : analyses the PDF asset against retrieved guidelines
                             (APIM MCP tool for PyMuPDF is added manually in the portal)
  - brandsense-briefer     : synthesises audit results into a creative brief

Usage:
    python scripts/deploy_foundry_agents.py \\
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
import sys
from typing import Optional

from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import (
    AzureAISearchTool,
    PromptAgentDefinition,
)
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient

logging.basicConfig(level=logging.INFO, format="[%(levelname)s] %(message)s")
logger = logging.getLogger(__name__)

# Key Vault secret names — brandsense-api reads these at startup
KV_SECRET_RESEARCHER = "brandsense-researcher-agent-id"
KV_SECRET_AUDITOR    = "brandsense-auditor-agent-id"
KV_SECRET_BRIEFER    = "brandsense-briefer-agent-id"

# Default Foundry connection name created by deploy.ps1 Phase 2.5
DEFAULT_SEARCH_CONNECTION_NAME = "brandsense-search"


# ---------------------------------------------------------------------------
# Agent system prompts
# ---------------------------------------------------------------------------

RESEARCHER_INSTRUCTIONS = """
You are the BrandSense Marketing Researcher.

Your sole responsibility is to retrieve the brand, legal, and SEO guidelines
that are relevant to the marketing asset under review.

## Tools
- AzureAISearch: query the `brandsense-guidelines` index.

## Behaviour
1. Receive a short description of the asset (file name, asset type, target market).
2. Run three searches against the guidelines index:
   - category:"brand"  â€” retrieve all brand rules
   - category:"legal"  â€” retrieve all legal requirements
   - category:"seo"    â€” retrieve all SEO rules
3. Return the retrieved guidelines as a structured JSON object with three keys:
   `brand`, `legal`, `seo` â€” each containing an array of guideline objects.

## Output format
```json
{
  "brand": [ { "id": "...", "rule": "...", "value": "...", "description": "..." } ],
  "legal": [ { "id": "...", "rule": "...", "value": "...", "jurisdiction": "...", "description": "..." } ],
  "seo":   [ { "id": "...", "rule": "...", "value": "...", "dimension": "...",   "description": "..." } ]
}
```

## Rules
- Do not fabricate guidelines. Only return what the search index returns.
- Do not perform any audit or analysis â€” that is the Auditor's job.
- If the search returns no results for a category, return an empty array for that key.
"""

AUDITOR_INSTRUCTIONS = """
You are the BrandSense Marketing Auditor.

You receive:
1. The full text content of a marketing asset (extracted from PDF).
2. Font and colour metadata extracted by the PyMuPDF tool via APIM.
3. The structured guidelines retrieved by the Researcher agent.

Your job is to audit the asset against every guideline and produce a structured
list of pass/fail checks.

## Behaviour
1. For each guideline in `brand`, `legal`, and `seo`:
   a. Evaluate whether the asset content / metadata complies.
   b. Record a check with: rule_id, category, pass_fail (bool), severity
      ("error" | "warning"), message, evidence (quoted excerpt or metric),
      and recommendation (if failed).
2. Compute summary counts: error_count, warning_count, overall_pass.

## Output format
```json
{
  "checks": [
    {
      "rule_id": "brand-001",
      "category": "brand",
      "pass_fail": false,
      "severity": "error",
      "message": "Primary blue #0078D4 not found in document colours.",
      "evidence": "Colours found: #FF5733, #FFFFFF",
      "recommendation": "Replace headline colour with #0078D4."
    }
  ],
  "error_count": 1,
  "warning_count": 0,
  "overall_pass": false
}
```

## Rules
- Be specific. Quote evidence from the asset or metadata.
- Do not invent colour or font values â€” only use what is provided in the metadata.
- If a guideline is not applicable to this asset type, mark it as pass with a
  note in the message field.
- severity "error" = blocking issue; "warning" = recommended fix.
"""

BRIEFER_INSTRUCTIONS = """
You are the BrandSense Marketing Briefer.

You receive the full audit result produced by the Auditor agent.

Your job is to synthesise the failed checks into a clear, actionable creative brief
that a marketing team can hand directly to a designer or copywriter.

## Behaviour
1. Group failed checks by theme (e.g., colour, typography, legal, tone of voice).
2. For each theme write a brief section with:
   - section: theme name
   - content: plain-English description of what needs to change and why
   - priority: "high" (errors) | "medium" (warnings)
3. Add an overall summary sentence.

## Output format
```json
{
  "summary": "The asset requires 3 corrections before it can be published.",
  "brief": [
    {
      "section": "Colour",
      "content": "Replace the headline colour (#FF5733) with the primary brand blue (#0078D4). Red is only permitted for error states in product UI.",
      "priority": "high"
    }
  ]
}
```

## Rules
- Only include sections where there are actual failures.
- Write for a non-technical audience â€” avoid jargon.
- If overall_pass is true, return a brief with a single section confirming
  the asset is compliant and ready to publish.
- Do not repeat the raw rule IDs in the brief â€” translate them into plain language.
"""


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
                    "Connection '%s' not found — attempting auto-discover.",
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
            "Create the connection with 'az ml connection create' then re-run."
        )
        return None

    def _search_tools(self) -> list:
        if not self.search_connection_id:
            return []
        return [
            AzureAISearchTool(
                index_connection_id=self.search_connection_id,
                index_name="brandsense-guidelines",
            )
        ]

    def _create_or_update(self, agent_name: str, instructions: str, tools: list) -> str:
        """Create or update a named agent and return its ID."""
        existing = None
        try:
            existing = self.project_client.agents.get_agent(agent_name)
        except Exception:
            pass  # agent does not exist yet

        if existing:
            agent = self.project_client.agents.update_agent(
                agent_id=existing.id,
                model=self.model_deployment,
                instructions=instructions,
                tools=tools,
            )
            logger.info("Updated  %-35s id=%s", agent_name, agent.id)
        else:
            agent = self.project_client.agents.create_agent(
                model=self.model_deployment,
                name=agent_name,
                instructions=instructions,
                tools=tools,
            )
            logger.info("Created  %-35s id=%s", agent_name, agent.id)

        return agent.id

    def _write_kv_secret(self, secret_name: str, value: str) -> None:
        self.kv_client.set_secret(secret_name, value)
        logger.info("Key Vault secret set: %s", secret_name)

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def deploy_all(self) -> dict:
        logger.info("=" * 60)
        logger.info("BrandSense — deploying Foundry agents")
        logger.info("  Project    : %s", self.project_endpoint)
        logger.info("  Model      : %s", self.model_deployment)
        logger.info("  KV         : %s", self.key_vault_name)
        logger.info("  Search conn: %s", self.search_connection_name or "(auto-discover)")
        logger.info("=" * 60)

        # Resolve AI Search connection ID from name (or auto-discover)
        self.search_connection_id = self._resolve_search_connection_id()
        search_tools = self._search_tools()
        results = {}

        try:
            results["researcher"] = self._create_or_update(
                "brandsense-researcher",
                RESEARCHER_INSTRUCTIONS,
                search_tools,
            )
            results["auditor"] = self._create_or_update(
                "brandsense-auditor",
                AUDITOR_INSTRUCTIONS,
                search_tools,  # APIM MCP tool added manually in Foundry portal
            )
            results["briefer"] = self._create_or_update(
                "brandsense-briefer",
                BRIEFER_INSTRUCTIONS,
                [],  # no tools â€” synthesis only
            )

            # Persist IDs to Key Vault
            self._write_kv_secret(KV_SECRET_RESEARCHER, results["researcher"])
            self._write_kv_secret(KV_SECRET_AUDITOR,    results["auditor"])
            self._write_kv_secret(KV_SECRET_BRIEFER,    results["briefer"])

            logger.info("=" * 60)
            logger.info("[OK] All agents deployed.")
            logger.info("  brandsense-researcher : %s", results["researcher"])
            logger.info("  brandsense-auditor    : %s", results["auditor"])
            logger.info("  brandsense-briefer    : %s", results["briefer"])
            logger.info("=" * 60)
            logger.info(
                "Next: add the APIM MCP Server connection to "
                "'brandsense-auditor' in the Foundry portal."
            )
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
    args = parser.parse_args()

    deployer = AgentDeployer(
        project_endpoint=args.project_endpoint,
        model_deployment=args.model_deployment,
        key_vault_name=args.key_vault_name,
        search_connection_name=args.search_connection_name,
    )
    deployer.deploy_all()


if __name__ == "__main__":
    main()
