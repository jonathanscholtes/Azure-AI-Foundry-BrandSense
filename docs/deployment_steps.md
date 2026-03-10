# BrandSense — Deployment Guide

> Back to [README](../README.md)

End-to-end deployment guide for BrandSense: AI-powered marketing asset validation on Microsoft Foundry.

---

## Prerequisites

### Tools

| Tool | Version | Install |
|---|---|---|
| Terraform | >= 1.5 | **Windows:** `winget install HashiCorp.Terraform` · **macOS:** `brew install hashicorp/tap/terraform` · **Linux:** [Install guide](https://developer.hashicorp.com/terraform/install) |
| Azure CLI | Latest | [Install guide](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) |
| PowerShell | 5.1+ (Windows) · 7+ (Linux/macOS) | **Windows:** Built-in (5.1) or `winget install Microsoft.PowerShell` for 7+ · **Linux/macOS:** [Install guide](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell) |
| Python | 3.11+ | Required to seed the guidelines index locally |
| Docker | Latest | Not required — images are built remotely via `az acr build`. Only needed if you want to build or test containers locally |
| Git | Latest | [Install guide](https://git-scm.com/downloads) |

### Azure Access Requirements

| Requirement | Reason |
|---|---|
| **Owner** or **Contributor** on the target subscription | Terraform creates all resource groups and resources |
| **User Access Administrator** on the subscription | Terraform assigns RBAC roles to the managed identity |

---

## Step 1 — Clone the Repository

```bash
git clone https://github.com/jonathanscholtes/Azure-AI-Foundry-BrandSense.git
cd Azure-AI-Foundry-BrandSense
```

---

## Step 2 — Login to Azure

```powershell
az login
az account set --subscription "YOUR-SUBSCRIPTION-ID"
```

---

## Step 3 — Deploy Infrastructure

Run the deployment orchestrator. This performs all phases automatically:

- **Phase 0** — Bootstrap Terraform remote state backend (idempotent)
- **Phase 1** — Deploy infrastructure via Terraform
- **Phase 1.5** — Build and push container images to ACR
- **Phase 2** — Seed the `brandsense-guidelines` AI Search index
- **Phase 3** — Deploy Foundry agents (researcher / auditor / briefer)
- **Phase 3.5** — Inject agent IDs and Foundry endpoint into the `brnd-api` Container App

**Windows:**
```powershell
.\deploy.ps1 -Subscription "YOUR-SUBSCRIPTION-ID"
```

**Linux / macOS:**
```powershell
pwsh ./deploy.ps1 -Subscription "YOUR-SUBSCRIPTION-ID"
```

**Optional parameters:**

| Parameter | Default | Description |
|---|---|---|
| `-Location` | `eastus2` | Azure region for all resources |
| `-Environment` | `dev` | Environment tag applied to resources |
| `-TfStateStorageAccount` | `stotfbrnd<8-char-sub-id>` | Override the Terraform state storage account name |
| `-TfStateResourceGroup` | `rg-tfstate-brnd` | Resource group for Terraform state storage |
| `-SkipBootstrap` | off | Skip Phase 0 (state backend already exists) |
| `-SetupGitHub` | off | Configure GitHub Actions OIDC secrets automatically (requires `gh` CLI) |
| `-Destroy` | off | Tear down all deployed resources |

> **Estimated time:** 20–45 minutes. API Management provisioning is the slowest resource (~30 min).

**Resources created:**

| Resource | Purpose |
|---|---|
| Azure AI Services (Microsoft Foundry) | GPT-4.1 + text-embedding-ada-002 model deployments, Foundry project |
| Azure AI Search | `brandsense-guidelines` index with vector + semantic search |
| API Management | MCP server endpoint for the Auditor agent |
| Container Registry | Stores `brnd-api` and `brnd-ui` images |
| Container Apps | Hosts `brnd-api` (FastAPI) and `brnd-ui` (React) |
| Key Vault | Stores agent IDs and Foundry project endpoint |
| User-Assigned Managed Identity | Runtime identity for Container Apps and Foundry calls |
| Application Insights + Log Analytics | Monitoring and diagnostics |
| Storage Account | PDF upload storage |

---

## Step 4 — Create the APIM MCP Server (Manual — Portal)

The `brnd-api` FastAPI service is deployed in APIM by Terraform. This step exposes it as an MCP server that the Auditor Foundry agent can call.

1. Open the **[Azure Portal](https://portal.azure.com)** and navigate to the **API Management** instance  
   *(Find it in the resource group, or use `terraform output apim_name` after deployment)*

2. In the left menu select **APIs → MCP Servers**

3. Click **+ Create** → **Expose an API as an MCP server**

4. Fill in the form:

   | Field | Value |
   |---|---|
   | **Name** | `brandsense-mcp` |
   | **API** | `BrandSense API` *(deployed by Terraform)* |
   | **Tools** | Select the `extract-fonts` operation |
   | **Description** | `BrandSense PDF analysis tools via Azure APIM. Provides font and color extraction from marketing asset PDFs for brand typography and color compliance auditing.` |

5. Click **Create**

6. Open the created MCP server entry and **copy the MCP Server endpoint URL**

   The URL format is:
   ```
   https://<apim-name>.azure-api.net/<mcp-path>/mcp
   ```

---

## Step 5 — Add the MCP Tool to the Auditor Agent (Manual — Foundry Portal)

The `brandsense-auditor` agent must be connected to the APIM MCP server. This is done manually in the Foundry portal because MCP tool connections are not yet configurable via the SDK at deployment time.

1. Open **[Microsoft Foundry](https://ai.azure.com/)** and navigate to your project

2. In the left menu go to **Build → Agents**

3. Select **brandsense-auditor**

4. Under **Tools**, click **+ Add tool** → **Model Context Protocol (MCP)**

5. Fill in the form:

   | Field | Value |
   |---|---|
   | **Name** | `brandsense-mcp` |
   | **Remote MCP Server endpoint** | The URL copied from Step 4 |
   | **Authentication** | `None` |

6. Click **Connect**, then **Save** the agent

---

## Step 6 — Verify the Deployment

```powershell
# Check Terraform outputs
cd infra
terraform output
```

Key outputs to note:

| Output | Description |
|---|---|
| `container_app_url` | BrandSense API — open `<url>/docs` to verify |
| `container_app_ui_url` | BrandSense UI |
| `apim_gateway_url` | APIM base URL |
| `search_service_endpoint` | AI Search endpoint |
| `ai_project_endpoint` | Foundry project endpoint |

Open the UI URL in a browser, upload a PDF, and confirm the three-agent pipeline runs to completion.

If all three agent stages complete and a scored brief is returned, the deployment is fully operational.

---

## GitHub Actions (Optional)

CI/CD is pre-configured in `.github/workflows/deploy.yml`. It requires three repository secrets:

| Secret | Description |
|---|---|
| `AZURE_CLIENT_ID` | Client ID of the GitHub Actions service principal |
| `AZURE_TENANT_ID` | Entra tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Target subscription ID |

Set these automatically by re-running deploy with the `-SetupGitHub` flag (requires the `gh` CLI and `gh auth login`):

```powershell
.\deploy.ps1 -Subscription "YOUR-SUBSCRIPTION-ID" -SetupGitHub
```

The workflow runs on push to `main` and uses path filters to only deploy what changed — it will not re-seed guidelines or redeploy agents unless their source files are modified.

---

## Teardown

```powershell
.\deploy.ps1 -Subscription "YOUR-SUBSCRIPTION-ID" -Destroy
```

This runs `terraform destroy` on all BrandSense resources. The Terraform state storage account (`rg-tfstate-brnd`) is **not** destroyed and must be removed manually if no longer needed.
