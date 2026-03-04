# BrandSense — Development Guide

> **Type:** Active development reference. Derived from `project.md` decisions.
> **Status:** M0 complete (planning). Starting M1 — Scaffold.
> **Stack:** Python (FastAPI) · React.js (JavaScript, Vite SPA) · Terraform · GitHub Actions · Microsoft Foundry

---

## Current State of the Repo

The repo contains Terraform infrastructure adapted from the **AI-Foundry-ITSM** project. Before writing any agent code, the infrastructure and naming must be updated for BrandSense. Several modules already exist and are reusable — they need variable/naming updates only.

| What exists | Status | Action needed |
|---|---|---|
| `infra/` — Terraform modules | Exists, ITSM-named | Update variable defaults + tags |
| `infra/modules/ai_services/` | Exists | Verify GPT-4.1 deployment name |
| `infra/modules/search/` | Exists | Reuse as-is |
| `infra/modules/container_registry/` | Exists | Reuse as-is |
| `infra/modules/identity/` | Exists | Reuse as-is |
| `infra/modules/storage/` | Exists | Update container names for BrandSense |
| `infra/modules/apim/` | Exists | **Re-enable** — needed to expose FastAPI as an MCP Server for Foundry tool discovery |
| `deploy.ps1` | Exists, ITSM script | Update for BrandSense deployment |
| Python agent code | Does not exist | Build from scratch (agent definitions deployed to Foundry) |
| Foundry agent definitions | Does not exist | Deploy via SDK after scaffold |
| `.github/workflows/` | Does not exist | Create |

---

## Step 1 — Update Terraform for BrandSense

### 1.1 Update `infra/variables.tf` defaults

Replace all ITSM-specific defaults with BrandSense naming:

| Variable | Current default | New default |
|---|---|---|
| `resource_group_name` | `rg-ai-foundry-itsm` | `rg-brandsense` |
| `project_name` | `aifoundry` | `brandsense` |
| `managed_identity_name` | `id-ai-foundry-main` | `id-brandsense-main` |
| `app_insights_name` | `appi-ai-foundry` | `appi-brandsense` |
| `search_service_name` | `aisearch-foundry` | `search-brandsense` |
| `storage_account_name` | `stoaifoundryitsm` | `stobrandsense` |
| `key_vault_name` | `kvfoundryitsm` | `kv-brandsense` |
| `container_registry_name` | `acraifoundryitsm` | `acrbrandsense` |
| `tags.Project` | `AI-Foundry-ITSM` | `BrandSense` |

### 1.2 Update `infra/variables.tf` — model deployment

Replace `gpt4o` capacity variable with `gpt41`:

```hcl
variable "ai_services_deployment_gpt41_capacity" {
  description = "Capacity for GPT-4.1 deployment"
  type        = number
  default     = 150
}
```

### 1.3 Add Container Apps module

A Container Apps module does not currently exist. Add `infra/modules/container_apps/` to host:
- **Python FastAPI** — entry point (`POST /validate`), PyMuPDF tool endpoint (`POST /tools/extract-fonts`), React UI static files
- **APIM** routes to the Container App and exposes the FastAPI as an MCP Server for Foundry

Agents run **in Microsoft Foundry** — not in the Container App.

```hcl
# infra/modules/container_apps/main.tf (to create)
# Resources: azurerm_container_app_environment, azurerm_container_app (x1)
```

### 1.4 Configure APIM as MCP Server

APIM is needed to expose the FastAPI server as an MCP Server so Foundry agents can discover and call tools automatically (no per-tool registration, no ngrok).

> **Note:** Terraform provisions the APIM resource (instance, products, subscriptions). The **MCP Server configuration** inside APIM is a **manual one-time step in the portal** — no Terraform resource exists for it. Perform this step after `terraform apply` completes and the Container App is running.

**After `terraform apply` — in Azure Portal:** APIM → APIs → MCP Servers → Create → **Expose an API as an MCP server**
- Import the FastAPI OpenAPI spec (from `https://<container-app-url>/openapi.json`)
- This creates an MCP Server endpoint: `https://<apim-name>.azure-api.net/mcp`
- The Marketing Auditor agent in Foundry is configured to connect to this MCP endpoint

Verify the APIM module is enabled in `infra/main.tf` and update its variables for BrandSense:

```hcl
# module "apim" — enabled; exposes FastAPI as MCP Server for Foundry tool discovery
module "apim" {
  source = "./modules/apim"
  # ... BrandSense-named variables
}
```

### 1.5 Update storage container names

In `infra/modules/storage/main.tf`, replace ITSM container names with BrandSense ones:

```hcl
storage_containers = ["assets-raw", "assets-processed", "briefs-output"]
```

### 1.6 Update `infra/terraform.tfvars`

```hcl
subscription_id      = "<your-subscription-id>"
resource_group_name  = "rg-brandsense"
location             = "eastus2"
environment          = "dev"
project_name         = "brandsense"
search_sku           = "basic"
container_registry_sku = "Basic"
```

---

## Step 2 — Repo Structure

Create the following directory layout:

```
Azure-AI-Foundry-BrandSense/
├── .github/
│   └── workflows/
│       ├── ci.yml                  # Build + test on PR
│       └── deploy.yml              # Deploy on merge to main
├── infra/                          # Terraform (already exists — update as above)
│   ├── modules/
│   │   ├── container_apps/         # NEW — add this module
│   │   └── ...existing modules...
├── src/
│   ├── agents/                     # Python — Foundry agent definition scripts (deployed to Foundry)
│   │   ├── marketing_researcher/
│   │   │   ├── agent.py            # Defines + deploys the Researcher agent to Foundry
│   │   │   └── __init__.py
│   │   ├── marketing_auditor/
│   │   │   ├── agent.py            # Defines + deploys the Auditor agent to Foundry
│   │   │   ├── chunker.py          # Chunking helper (called by Auditor tool logic)
│   │   │   ├── aggregator.py       # Result aggregation helper
│   │   │   └── __init__.py
│   │   └── marketing_briefer/
│   │       ├── agent.py            # Defines + deploys the Briefer agent to Foundry
│   │       └── __init__.py
│   ├── workflow/
│   │   └── pipeline.py             # Calls Foundry Workflow API: trigger run, await BrieferOutput
│   ├── tools/
│   │   ├── document_intelligence.py  # Azure AI Document Intelligence wrapper
│   │   └── pymupdf.py              # PyMuPDF extraction — called by the FastAPI tool endpoint
│   ├── api/
│   │   └── server.py               # FastAPI server:
│   │                               #   POST /validate — triggers Foundry workflow, returns BrieferOutput
│   │                               #   POST /tools/extract-fonts — PyMuPDF tool endpoint (called by Foundry Auditor agent)
│   │                               #   GET  /health
│   │                               #   GET  / — serves React UI static files
│   ├── contracts.py                # Pydantic models (agent communication contracts)
│   └── config.py                   # Env var loading (pydantic-settings)
├── ui/                             # React.js SPA (Vite + JavaScript)
│   ├── src/
│   │   ├── components/
│   │   │   ├── AssetUpload.jsx     # PDF drag-and-drop upload
│   │   │   ├── ResultScore.jsx     # Score display (0–10)
│   │   │   ├── IssueList.jsx       # Brand / legal / SEO check results
│   │   │   └── BriefPanel.jsx      # Detailed brief output
│   │   ├── pages/
│   │   │   └── Home.jsx            # Main PoC page
│   │   ├── theme.js                # MUI custom theme
│   │   ├── App.jsx
│   │   └── main.jsx
│   ├── index.html
│   ├── vite.config.js
│   └── package.json
├── samples/
│   └── sample_branding_asset.pdf   # Test asset for local dev and demo
├── tests/
│   ├── unit/
│   └── integration/
├── requirements.txt
├── pyproject.toml
├── Dockerfile
├── .env.example
├── deploy.ps1                      # Update for BrandSense
└── project.md
```

---

## Step 3 — Python Agent Communication Contracts

Create `src/contracts.py` first — all agents and the pipeline depend on these models:

```python
# src/contracts.py
from __future__ import annotations
from typing import Optional
from pydantic import BaseModel, Field


# --- Marketing Researcher output ---

class BrandGuideline(BaseModel):
    rule: str
    value: str

class LegalRequirement(BaseModel):
    rule: str
    jurisdiction: Optional[str] = None

class SeoRule(BaseModel):
    rule: str
    dimension: str

class ResearcherOutput(BaseModel):
    brand_guidelines: list[BrandGuideline]
    legal_requirements: list[LegalRequirement]
    seo_rules: list[SeoRule]
    source_citations: list[str]


# --- Marketing Auditor output ---

class Check(BaseModel):
    rule: str
    passed: bool                          # 'pass' is a Python keyword
    issue: Optional[str] = None
    page_refs: Optional[list[int]] = None

class AuditorOutput(BaseModel):
    brand_checks: list[Check]
    legal_checks: list[Check]
    seo_checks: list[Check]
    overall_pass: bool


# --- Marketing Briefer output ---

class BriefDetail(BaseModel):
    scope: str
    brand_issues: list[str]
    legal_issues: list[str]
    seo_issues: list[str]
    actions: list[str]

class BrieferOutput(BaseModel):
    score: int = Field(..., ge=0, le=10)
    feedback: str
    brief: BriefDetail
```

---

## Step 4 — PyMuPDF Tool Endpoint + APIM MCP Server

Because agents run inside Microsoft Foundry, tools are discovered and called via the **MCP protocol**. The FastAPI server exposes `POST /tools/extract-fonts` as a standard route; APIM imports the OpenAPI spec and surfaces it as an MCP Server. The Foundry Auditor agent connects to the APIM MCP endpoint and discovers all tools automatically — no manual per-tool registration and no ngrok.

### `src/tools/pymupdf.py` — extraction logic

```python
import fitz  # PyMuPDF


def extract_font_color_metadata(pdf_bytes: bytes) -> dict:
    doc = fitz.open(stream=pdf_bytes, filetype="pdf")
    fonts: list[dict] = []
    colors: list[str] = []

    for page in doc:
        for block in page.get_text("dict")["blocks"]:
            for line in block.get("lines", []):
                for span in line.get("spans", []):
                    entry = {
                        "font": span["font"],
                        "size": round(span["size"], 2),
                        "color": hex(span["color"]),
                        "page": page.number + 1,
                    }
                    fonts.append(entry)
                    colors.append(hex(span["color"]))

    return {
        "fonts": fonts,
        "unique_fonts": list({f["font"] for f in fonts}),
        "unique_colors": list(set(colors)),
        "metadata": doc.metadata,
    }
```

### `src/api/server.py` — FastAPI server (partial)

```python
from fastapi import FastAPI, UploadFile, Form
from fastapi.staticfiles import StaticFiles
from src.tools.pymupdf import extract_font_color_metadata
from src.workflow.pipeline import run_pipeline
from src.contracts import BrieferOutput

app = FastAPI(
    title="BrandSense API",
    description="Marketing asset validation API. Exposed as an MCP Server via APIM.",
    version="0.1.0",
)


@app.post("/validate", response_model=BrieferOutput)
async def validate(file: UploadFile, context: str = Form(...)):
    """Entry point for the React UI. Triggers the Foundry workflow."""
    pdf_bytes = await file.read()
    return await run_pipeline(pdf_bytes=pdf_bytes, context=context)


@app.post("/tools/extract-fonts")
async def extract_fonts(file: UploadFile):
    """Extracts exact font families, sizes, and color values from a PDF.
    Exposed as an MCP tool via APIM — called by the Foundry Marketing Auditor agent."""
    pdf_bytes = await file.read()
    return extract_font_color_metadata(pdf_bytes)


@app.get("/health")
def health():
    return {"status": "ok"}


# Serve the built React SPA (ui/dist/) in production
app.mount("/", StaticFiles(directory="ui/dist", html=True), name="ui")
```

### Configure APIM MCP Server

> ⚠️ **Manual step — no Terraform support.** Terraform provisions the APIM instance; the MCP Server configuration inside APIM has no Terraform resource and must be done once in the portal after deploy.

Once the Container App is deployed, configure the APIM MCP Server:

1. **Azure Portal:** APIM → APIs → MCP Servers → Create → **Expose an API as an MCP server**
2. Import from: `https://<container-app-url>/openapi.json`
3. APIM creates an MCP endpoint: `https://<apim-name>.azure-api.net/mcp`
4. **In Foundry:** configure the Marketing Auditor agent to use this MCP endpoint — Foundry discovers `extract_font_color_metadata` automatically

No manual tool URL registration. No ngrok. APIM always routes to the deployed Container App.

## Step 5 — Python Project Setup

### `requirements.txt`

```
azure-ai-projects
azure-identity
azure-search-documents
azure-ai-documentintelligence
fastapi
uvicorn[standard]
python-multipart
PyMuPDF
openai
pydantic
pydantic-settings
httpx
pytest
ruff
```

### `pyproject.toml`

```toml
[project]
name = "brandsense"
version = "0.1.0"
requires-python = ">=3.11"

[tool.ruff]
line-length = 120

[tool.pytest.ini_options]
testpaths = ["tests"]
```

### `Dockerfile` (root — single image)

```dockerfile
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY src/ ./src/
CMD ["uvicorn", "src.api.server:app", "--host", "0.0.0.0", "--port", "80"]
```

### `.env.example`

```env
# Azure
AZURE_SUBSCRIPTION_ID=
AZURE_RESOURCE_GROUP=rg-brandsense
AZURE_TENANT_ID=
AZURE_CLIENT_ID=

# Microsoft Foundry
FOUNDRY_PROJECT_CONNECTION_STRING=

# Azure OpenAI
AZURE_OPENAI_ENDPOINT=
AZURE_OPENAI_DEPLOYMENT_GPT41=gpt-4.1
AZURE_OPENAI_DEPLOYMENT_GPT41_VISION=gpt-4.1

# Azure AI Search
AZURE_SEARCH_ENDPOINT=
AZURE_SEARCH_INDEX_NAME=brandsense-guidelines

# Azure AI Document Intelligence
AZURE_DOCUMENT_INTELLIGENCE_ENDPOINT=

# Azure Blob Storage
AZURE_STORAGE_ACCOUNT_NAME=stobrandsense
AZURE_STORAGE_CONTAINER_ASSETS=assets-raw

# FastAPI server base URL — used by APIM as the MCP Server backend
# Production: Container App URL (set by Terraform output)
# Local dev: deploy a dev Container App to Azure and use its URL
FASTAPI_BASE_URL=https://brandsense-api.azurecontainerapps.io

# APIM MCP Server endpoint — configured in Foundry Auditor agent
APIM_MCP_ENDPOINT=https://apim-brandsense.azure-api.net/mcp
```

---

## Step 6 — GitHub Actions Pipelines

### `.github/workflows/ci.yml` — runs on every PR

```yaml
name: CI

on:
  pull_request:
    branches: [main]

jobs:
  python:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.11'
      - run: pip install -r requirements.txt
      - run: ruff check src/ tests/
      - run: pytest tests/

  ui:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      - run: npm ci
        working-directory: ui
      - run: npm run build
        working-directory: ui

  terraform-plan:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3
      - uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
      - run: terraform init
        working-directory: infra
      - run: terraform plan
        working-directory: infra
```

### `.github/workflows/deploy.yml` — runs on merge to main

```yaml
name: Deploy

on:
  push:
    branches: [main]

jobs:
  build-and-push:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    steps:
      - uses: actions/checkout@v4
      - uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
      - name: Build & push Python API image
        run: |
          az acr build --registry ${{ secrets.AZURE_CONTAINER_REGISTRY }} \
            --image brandsense-api:${{ github.sha }} .

  terraform-apply:
    needs: build-and-push
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3
      - uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
      - run: terraform init
        working-directory: infra
      - run: terraform apply -auto-approve
        working-directory: infra

  validate:
    needs: terraform-apply
    runs-on: ubuntu-latest
    steps:
      - name: Health check
        run: curl --fail ${{ secrets.API_HEALTH_CHECK_URL }}/health
```

### GitHub Actions secrets to configure

| Secret | Value |
|---|---|
| `AZURE_CLIENT_ID` | App registration / managed identity client ID |
| `AZURE_TENANT_ID` | Azure tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Azure subscription ID |
| `AZURE_CONTAINER_REGISTRY` | ACR login server (e.g. `acrbrandsense.azurecr.io`) |
| `TF_STATE_STORAGE_ACCOUNT` | Storage account for Terraform remote state |
| `API_HEALTH_CHECK_URL` | Container App URL after deploy |

---

## Step 7 — Development Order (Milestones)

### M1 — Scaffold (Week 2)
- [ ] Update `infra/variables.tf` defaults for BrandSense
- [ ] Add `infra/modules/container_apps/` module (1 Container App)
- [ ] Enable and configure APIM module in Terraform (`module "apim"` in `infra/main.tf`, update naming variables)
- [ ] **After `terraform apply`** — manually configure APIM MCP Server in the portal (APIM → APIs → MCP Servers → Create → Expose an API as an MCP server)
- [ ] Update storage container names
- [ ] Create `src/contracts.py` (Pydantic models)
- [ ] Create `requirements.txt`, `pyproject.toml`, `Dockerfile`, `.env.example`
- [ ] Scaffold `ui/` — `npm create vite@latest ui -- --template react`
- [ ] Install UI dependencies: `@mui/material @mui/icons-material @emotion/react @emotion/styled`
- [ ] Create `.github/workflows/ci.yml` and `deploy.yml`
- [ ] Add all GitHub Actions secrets to the repository
- [ ] Run `terraform init && terraform plan` — verify clean plan

### M2 — Marketing Researcher (Weeks 3–4)
- [ ] Create AI Search index `brandsense-guidelines` (Terraform or portal for initial setup)
- [ ] Load brand guideline documents into AI Search
- [ ] Implement `src/agents/marketing_researcher/agent.py`
  - Use Foundry SDK to create/update the Researcher agent in Foundry
  - System prompt: retrieve brand, legal, SEO requirements from knowledge base
  - Tools registered in Foundry: Azure AI Search, SharePoint tool, Bing grounding
- [ ] Implement `src/agents/marketing_researcher/__init__.py` — deploy agent, return Foundry agent ID
- [ ] Unit test: given a query, verify structured output schema

### M3 — Marketing Auditor (Weeks 5–7)
- [ ] Implement `src/tools/pymupdf.py` — extraction logic
- [ ] Implement `POST /tools/extract-fonts` route on FastAPI server (with OpenAPI docstring for MCP discovery)
- [ ] Deploy Container App and verify `/openapi.json` is reachable
- [ ] Configure APIM MCP Server: APIM → APIs → MCP Servers → Create → Expose an API as an MCP server *(manual portal step — no Terraform resource)*
- [ ] Implement `src/tools/document_intelligence.py` — call Document Intelligence, return extracted text
- [ ] Implement `src/agents/marketing_auditor/chunker.py` — split document into page chunks
- [ ] Implement `src/agents/marketing_auditor/agent.py`
  - Use Foundry SDK to create/update the Auditor agent in Foundry
  - Configure agent to connect to APIM MCP endpoint — Foundry discovers `extract_font_color_metadata` automatically
  - System prompt: per chunk, validate brand / legal / SEO against `ResearcherOutput`; call PyMuPDF tool for exact font/color; call GPT-4.1 Vision for visual checks
- [ ] Implement `src/agents/marketing_auditor/aggregator.py` — deduplicate, consolidate, emit `AuditorOutput`
- [ ] Integration test: submit a sample PDF, verify `AuditorOutput` schema and issue detection

### M4 — Marketing Briefer (Week 8)
- [ ] Implement `src/agents/marketing_briefer/agent.py`
  - Use Foundry SDK to create/update the Briefer agent in Foundry
  - System prompt: synthesize `AuditorOutput` into score, narrative feedback, and detailed brief
  - Score logic: weighted across brand / legal / SEO check results
- [ ] Return typed `BrieferOutput`
- [ ] Unit test: given a mock `AuditorOutput`, verify score range and brief structure

### M5 — Integration (Week 9)
- [ ] Implement `src/workflow/pipeline.py` — call Foundry Workflow API to trigger Researcher → Auditor → Briefer run; await completion; return `BrieferOutput`
- [ ] Implement `src/api/server.py` — `POST /validate` triggers workflow, `POST /tools/extract-fonts` serves PyMuPDF (MCP-discoverable), `GET /health`, React UI static files
- [ ] Deploy all three agent definitions to Foundry (run `src/agents/*/agent.py`)
- [ ] Verify Foundry Auditor agent calls `extract_font_color_metadata` via APIM MCP endpoint
- [ ] Error handling: agent failures, timeouts, oversized documents
- [ ] Logging: structured JSON logs per agent step (for Application Insights)
- [ ] End-to-end test with `samples/sample_branding_asset.pdf`

### M6 — Demo (Week 10)
- [ ] Deploy full stack to Azure via GitHub Actions
- [ ] Validate with a real customer brand asset
- [ ] Review output with stakeholders: score, feedback, brief
- [ ] Capture open issues for v2

---

## Step 8 — UI (React + Vite + MUI v5)

A lightweight SPA for submitting assets and viewing results. Used for PoC testing and customer demos — no auth required for v1.

### Scaffold

```powershell
npm create vite@latest ui -- --template react
cd ui
npm install @mui/material @mui/icons-material @emotion/react @emotion/styled axios
```

### `ui/src/theme.js` — MUI custom theme

```javascript
import { createTheme } from '@mui/material/styles';

export const theme = createTheme({
  palette: {
    primary:   { main: '#0078D4' },  // Microsoft blue
    secondary: { main: '#50E6FF' },
    background: { default: '#F5F5F5' },
  },
  typography: {
    fontFamily: '"Segoe UI", Roboto, sans-serif',
  },
});
```

### `ui/src/pages/Home.jsx` — main page structure

```jsx
import { useState } from 'react';
import { Container, Typography, Box } from '@mui/material';
import AssetUpload from '../components/AssetUpload';
import ResultScore from '../components/ResultScore';
import IssueList from '../components/IssueList';
import BriefPanel from '../components/BriefPanel';

export default function Home() {
  const [result, setResult] = useState(null);

  return (
    <Container maxWidth="lg" sx={{ py: 4 }}>
      <Typography variant="h3" fontWeight={700} gutterBottom>
        BrandSense
      </Typography>
      <Typography variant="subtitle1" color="text.secondary" gutterBottom>
        Upload a marketing asset to validate brand, legal, and SEO compliance.
      </Typography>
      <Box mt={4}>
        <AssetUpload onResult={setResult} />
      </Box>
      {result && (
        <Box mt={4} display="flex" flexDirection="column" gap={3}>
          <ResultScore score={result.score} feedback={result.feedback} />
          <IssueList
            brandIssues={result.brief.brand_issues}
            legalIssues={result.brief.legal_issues}
            seoIssues={result.brief.seo_issues}
          />
          <BriefPanel brief={result.brief} />
        </Box>
      )}
    </Container>
  );
}
```

### `ui/src/components/AssetUpload.jsx`

```jsx
import { useState } from 'react';
import { Box, Button, TextField, CircularProgress, Alert } from '@mui/material';
import UploadFileIcon from '@mui/icons-material/UploadFile';
import axios from 'axios';

export default function AssetUpload({ onResult }) {
  const [file, setFile]       = useState(null);
  const [context, setContext] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError]     = useState(null);

  const handleSubmit = async () => {
    if (!file) return;
    setLoading(true); setError(null);
    const form = new FormData();
    form.append('file', file);
    form.append('context', context);
    try {
      const { data } = await axios.post('/api/validate', form);
      onResult(data);
    } catch (e) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <Box display="flex" flexDirection="column" gap={2}>
      <Button variant="outlined" component="label" startIcon={<UploadFileIcon />}>
        {file ? file.name : 'Select PDF'}
        <input type="file" accept="application/pdf" hidden
          onChange={e => setFile(e.target.files?.[0] ?? null)} />
      </Button>
      <TextField
        label="Campaign context"
        placeholder="e.g. Q2 product launch for Azure AI"
        value={context}
        onChange={e => setContext(e.target.value)}
        fullWidth
      />
      <Button variant="contained" onClick={handleSubmit}
        disabled={!file || loading}
        startIcon={loading ? <CircularProgress size={18} /> : undefined}>
        {loading ? 'Validating…' : 'Validate Asset'}
      </Button>
      {error && <Alert severity="error">{error}</Alert>}
    </Box>
  );
}
```

### `ui/vite.config.js` — proxy API calls to backend

```javascript
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      '/api': 'http://localhost:80',  // Python FastAPI
    },
  },
});
```

### Local dev — run UI alongside API

```powershell
# Terminal 1 — Python API
uvicorn src.api.server:app --port 80 --reload

# Terminal 2 — UI
cd ui
npm run dev
# Opens at http://localhost:5173
```

### UI hosting

For the PoC, the Vite SPA is built (`npm run build`) and served as static files from the FastAPI server (e.g. `StaticFiles` mount on `/`). No separate Container App is needed for the UI in v1 — it ships in the same Python container.

---

## Local Development

### Prerequisites

- Node.js 20+ (for UI only)
- Python 3.11+
- Docker Desktop
- Terraform 1.7+
- Azure CLI (`az login`)
- Access to Azure subscription with Microsoft Foundry project and APIM instance created

### First-time setup

```powershell
# Clone repo
git clone https://github.com/your-org/Azure-AI-Foundry-BrandSense.git
cd Azure-AI-Foundry-BrandSense

# Python dependencies
pip install -r requirements.txt

# Copy and fill env vars
cp .env.example .env
# Edit .env with your Azure endpoints and credentials

# Start Python FastAPI (exposes /validate and /tools/extract-fonts)
uvicorn src.api.server:app --port 80 --reload

# APIM always routes to the deployed Container App URL — no tunnel needed.
# For local dev, deploy to a dev Container App and point APIM to that URL.
# Test the tool endpoint directly against the local FastAPI before deploying:
```

### UI first-time setup

```powershell
cd ui
npm install
npm run dev
# Opens at http://localhost:5173 (proxies /api to :80)
```

### Test a document locally

```powershell
curl -X POST http://localhost:80/validate \
  -F "file=@samples/sample_branding_asset.pdf" \
  -F "context=Q2 product launch campaign"
```

---

## Key Decisions Reference

All architectural decisions are recorded in [project.md](project.md). Summary of what drives implementation choices:

| Decision | Decided |
|---|---|
| Agent pipeline | Sequential: Researcher → Auditor → Briefer |
| Agent hosting | Microsoft Foundry Agent Service — agents deployed to and executed in Foundry |
| Tool discovery | APIM MCP Server — APIM imports FastAPI OpenAPI spec and exposes it as an MCP Server; Foundry Auditor agent connects to the MCP endpoint |
| Language | Python — all agents, API, and tooling (including PyMuPDF) |
| Font/color extraction | PyMuPDF — `src/tools/pymupdf.py`; exposed as `POST /tools/extract-fonts` on FastAPI; discovered by Foundry via APIM MCP Server |
| Visual brand checks | GPT-4.1 Vision (page rendered as image) |
| Text extraction | Azure AI Document Intelligence |
| Large documents | Chunk-and-aggregate in Auditor |
| Infrastructure | Terraform |
| CI/CD | GitHub Actions |
| Auth | Managed Identity (OIDC in GitHub Actions) |
| Orchestration | Microsoft Foundry Workflows |
| Frontend | React.js (Vite SPA, JavaScript) + MUI v5 + Emotion |

---

## UI Strategy

### Development & Agent Testing — No UI needed

Microsoft Foundry provides a built-in **Agent Playground** in the portal. Use it throughout M2–M4 to test each agent individually before wiring the pipeline:

- Open the Foundry project in the Azure portal
- Navigate to **Agents** → select the agent → **Test in playground**
- Send test prompts directly, inspect tool calls, view raw outputs
- No code needed — ideal for validating agent behaviour before integration

For the full pipeline (M5), use `curl` or a REST client (e.g. Postman / Thunder Client in VS Code) against the `/validate` endpoint:

```powershell
curl -X POST http://localhost:80/validate `
  -F "file=@samples/sample_branding_asset.pdf" `
  -F "context=Q2 product launch campaign"
```

### Customer PoC Demo — React UI (build in M6)

A raw API response is not a compelling customer demo. The React SPA (built in Step 8) turns the PoC into something a customer can understand and engage with.

**What the UI needs to do:**
- File upload input (PDF)
- Context text field (e.g. "Q2 product launch campaign")
- Submit button → POST to `/validate`
- Display: compliance score, feedback narrative, and brief issues grouped by brand / legal / SEO

**What it does NOT need:**
- Auth / login (PoC only)
- User accounts or history
- Mobile responsiveness
- Production-grade error handling

**Tech:** React.js (Vite, JavaScript) · MUI v5 (`@mui/material`) · Emotion · served as FastAPI static files

> **Timing:** Do not build the UI until M5 integration is complete and the API returns correct results. A UI built on a broken pipeline wastes time.
