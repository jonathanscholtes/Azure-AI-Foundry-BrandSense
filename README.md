# BrandSense

AI-powered marketing asset validation using Microsoft Azure AI Foundry.

BrandSense ingests PDF marketing assets and runs them through a three-agent pipeline that checks brand compliance, legal requirements, and SEO best practices, then produces a structured creative brief.

## Architecture

```
User uploads PDF
      │
      ▼
brandsense-researcher   ← queries brandsense-guidelines index (AI Search)
      │
      ▼
brandsense-auditor      ← analyses PDF via PyMuPDF MCP tool (APIM)
      │
      ▼
brandsense-briefer      ← synthesises results into a scored creative brief
```

**Infrastructure**: Azure AI Foundry · AI Search · Container Apps · API Management · Container Registry · Key Vault · Storage

## Prerequisites

- Azure CLI (`az login`)
- Terraform ≥ 1.6
- PowerShell 7+
- Python 3.12+
- Docker (for local image builds)
- GitHub CLI (`gh auth login`) — only for `-SetupGitHub`

## First-time deployment

```powershell
.\deploy.ps1 -Subscription '<your-subscription-name-or-id>' -SetupGitHub
```

This runs four phases:

| Phase | What happens |
|---|---|
| 0 | Terraform remote state backend (Storage Account + container) |
| 1 | All Azure infrastructure via Terraform |
| 1.5 | Container images built and pushed to ACR |
| 2 | AI Search guidelines index seeded |
| 3 | Foundry agents deployed, IDs written to Key Vault |
| 4 | Entra app registration + GitHub secrets configured |

Subsequent deploys (infrastructure already exists):

```powershell
.\deploy.ps1 -Subscription '<subscription>' -SkipBootstrap
```

## GitHub Actions OIDC setup

`-SetupGitHub` creates the Entra app registration and sets three repository secrets automatically. However, your organisation's Conditional Access policy may block the CLI from creating the federated identity credential. If the Actions workflow fails with `AADSTS70025: no configured federated identity credentials`, create it manually:

1. **[portal.azure.com](https://portal.azure.com)** → **Microsoft Entra ID** → **App registrations**
2. Open **`sp-brnd-github`**
3. **Certificates & secrets** → **Federated credentials** → **Add credential**
4. Fill in:

   | Field | Value |
   |---|---|
   | Scenario | GitHub Actions deploying Azure resources |
   | Organization | `jonathanscholtes` |
   | Repository | `Azure-AI-Foundry-BrandSense` |
   | Entity type | Branch |
   | Branch | `main` |
   | Name | `github-actions-main` |

5. Click **Add**, then re-run the failed workflow.

> Before pushing, run `deploy.ps1` once locally to apply the Terraform role assignments that grant the GitHub SP access to Key Vault and AI Foundry. Without this the `deploy-agents` job will fail with a 403.

## GitHub Actions — what triggers what

| Files changed | Jobs that run |
|---|---|
| `apps/services/brandsense-api/**` | `deploy-api` only |
| `apps/ui/**` | `deploy-ui` only |
| `agents/researcher.py` | `deploy-agents --only researcher` |
| `agents/auditor.py` | `deploy-agents --only auditor` |
| `agents/briefer.py` | `deploy-agents --only briefer` |
| `agents/deploy.py` / shared | `deploy-agents` (all agents) |
| `scripts/load/data/**` | `seed-guidelines` only |

## Manual post-deploy steps

Two steps require the Azure portal — they cannot be automated through the public API:

### 1. APIM MCP Server

Expose the brandsense-api as an MCP server so the Auditor agent can call PyMuPDF tools:

1. **API Management** → **APIs** → **+ Add API** → **MCP Server**
2. Import OpenAPI spec from `https://<container-app-url>/openapi.json`
3. Note the MCP endpoint URL

### 2. Add MCP tool to brandsense-auditor

1. **AI Foundry portal** → **Agents** → `brandsense-auditor` → **Tools** → **Add tool** → **MCP**
2. Tool type: Remote MCP Server
3. URL: the APIM MCP endpoint from step 1
4. Connection: create a Custom Keys connection with the APIM subscription key

## Repository structure

```
agents/                 Agent definitions + deploy script
apps/
  services/
    brandsense-api/     FastAPI backend (PyMuPDF, pipeline orchestration)
  ui/                   React + Vite frontend
infra/                  Terraform (modules for every Azure service)
scripts/
  load/                 AI Search guidelines seeding
  Deploy-*.ps1          Phase scripts called by deploy.ps1
  New-GitHubOidc.ps1    OIDC app registration setup
docs/                   Project planning documents
deploy.ps1              Main deployment orchestrator
```

## Agents

| Agent | Foundry name | Key Vault secret | Uses AI Search |
|---|---|---|---|
| Researcher | `brandsense-researcher` | `brandsense-researcher-agent-id` | Yes |
| Auditor | `brandsense-auditor` | `brandsense-auditor-agent-id` | Yes |
| Briefer | `brandsense-briefer` | `brandsense-briefer-agent-id` | No |

To redeploy a single agent:

```powershell
.\scripts\Deploy-FoundryAgents.ps1 `
    -AiProjectEndpoint '<endpoint>' `
    -KeyVaultName '<kv-name>' `
    -Only auditor
```
