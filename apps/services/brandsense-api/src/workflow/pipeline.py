"""BrandSense agent pipeline.

Orchestrates the three-agent sequential workflow via deployed Foundry agents:
  1. Marketing Researcher  - retrieves brand/legal/SEO requirements from AI Search
  2. Marketing Auditor     - checks the asset against those requirements
  3. Marketing Briefer     - synthesises findings into a scored brief

Each agent is pre-deployed to Foundry (by ``scripts/deploy_foundry_agents.py``)
and its name is stored in Key Vault.  The pipeline calls each agent via the
``azure-ai-projects`` v2 SDK using the OpenAI Responses API with an
``agent_reference`` extra body parameter.

The pipeline pre-extracts text and font/colour metadata from the PDF and
passes them as context to the Auditor so the agent can run its checks without
needing a separate file-upload round-trip.

If Foundry is **not** configured (no connection string or agent names) the
pipeline falls back to a stub that returns placeholder results so the UI
can be tested independently.

The pipeline is an **async generator** that yields ndjson lines so the
FastAPI endpoint can stream progress back to the UI as each agent runs.

Event shapes (each is a JSON object on its own line):
  {"event": "progress", "agent": "researcher", "status": "running", "message": "..."}
  {"event": "progress", "agent": "researcher", "status": "done",    "message": "..."}
  ... (auditor, briefer follow the same pattern)
  {"event": "complete", "result": { ...BrieferOutput... }}
  {"event": "error",    "message": "..."}   # only emitted on failure
"""

import json
import logging
import re
from typing import AsyncGenerator

import fitz  # PyMuPDF
from azure.ai.projects.aio import AIProjectClient
from azure.identity.aio import DefaultAzureCredential, ManagedIdentityCredential
from openai import AsyncOpenAI

from config import settings
from models import BrieferOutput, BriefDetail, ProgressEvent, CompleteEvent, ErrorEvent
from tools.pymupdf import extract_font_color_metadata

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _progress(agent: str, status: str, message: str) -> str:
    """Serialise a ProgressEvent to an ndjson line (includes trailing newline)."""
    return json.dumps(ProgressEvent(agent=agent, status=status, message=message).model_dump()) + "\n"


def _extract_text(pdf_bytes: bytes) -> str:
    """Extract plain text from all pages of a PDF using PyMuPDF."""
    doc = fitz.open(stream=pdf_bytes, filetype="pdf")
    pages = [page.get_text() for page in doc]
    doc.close()
    return "\n\n".join(pages)


def _get_project_client() -> AIProjectClient:
    """Create an authenticated async AIProjectClient for the Foundry project."""
    if settings.azure_client_id:
        credential = ManagedIdentityCredential(client_id=settings.azure_client_id)
    else:
        credential = DefaultAzureCredential()
    return AIProjectClient(
        endpoint=settings.foundry_project_connection_string,
        credential=credential,
    )


async def _run_agent(openai_client: AsyncOpenAI, agent_name: str, message: str) -> str:
    """Run a single Foundry agent via the OpenAI Responses API.

    Uses ``agent_reference`` in ``extra_body`` to route the request to the
    named hosted agent.  The agent runs server-side (including any tool
    calls such as AI Search) and returns a completed response.

    The agent ID stored in Key Vault is in ``name:version`` format
    (e.g. ``brandsense-researcher:1``).  The Responses API requires these
    as separate fields; passing the combined string as ``name`` causes a
    404 "with version  not found" error.

    Raises ``RuntimeError`` if the response does not complete successfully.
    """
    # Split "name:version" (produced by create_version) into separate fields
    if ":" in agent_name:
        ref_name, ref_version = agent_name.rsplit(":", 1)
    else:
        ref_name, ref_version = agent_name, None

    agent_ref: dict = {"type": "agent_reference", "name": ref_name}
    if ref_version:
        agent_ref["version"] = ref_version

    response = await openai_client.responses.create(
        input=message,
        extra_body={"agent_reference": agent_ref},
    )

    if response.status != "completed":
        error_detail = ""
        if response.error:
            error_detail = f": {response.error.message}"
        raise RuntimeError(
            f"Agent run failed with status {response.status}{error_detail}"
        )

    text = response.output_text
    if not text:
        raise RuntimeError("Agent produced no text response")

    return text


def _parse_briefer_output(raw: str) -> BrieferOutput:
    """Parse the Briefer agent's JSON response into a ``BrieferOutput`` model.

    Handles common quirks: markdown code fences, leading prose before JSON, etc.
    """
    text = raw.strip()

    # Strip ```json ... ``` fences
    if "```" in text:
        text = re.sub(r"```(?:json)?\s*", "", text)

    # Try full text first, then fall back to first embedded JSON object
    try:
        return BrieferOutput(**json.loads(text))
    except (json.JSONDecodeError, ValueError):
        match = re.search(r"\{.*\}", text, re.DOTALL)
        if match:
            return BrieferOutput(**json.loads(match.group()))
        raise RuntimeError(
            f"Could not parse Briefer output as JSON.\nRaw output: {text[:500]}"
        )


# ---------------------------------------------------------------------------
# Stub pipeline (Foundry not configured)
# ---------------------------------------------------------------------------

async def _run_stub_pipeline() -> AsyncGenerator[str, None]:
    """Yield stub progress events and a placeholder result."""
    yield _progress("researcher", "running", "Retrieving brand, legal, and SEO guidelines…")
    yield _progress("researcher", "done", "Guidelines loaded")

    yield _progress("auditor", "running", "Analysing asset against guidelines…")
    yield _progress("auditor", "done", "Audit complete")

    yield _progress("briefer", "running", "Generating creative brief…")
    yield _progress("briefer", "done", "Brief ready")

    result = BrieferOutput(
        score=0,
        feedback=(
            "Pipeline stub — Foundry agents are not configured. "
            "Set FOUNDRY_PROJECT_CONNECTION_STRING and agent IDs to enable the real pipeline."
        ),
        brief=BriefDetail(
            scope="Pending configuration",
            brand_issues=[],
            legal_issues=[],
            seo_issues=[],
            actions=[
                "Configure Foundry project connection string",
                "Deploy agents with deploy_foundry_agents.py",
            ],
        ),
    )
    yield json.dumps(CompleteEvent(result=result).model_dump()) + "\n"


# ---------------------------------------------------------------------------
# Main pipeline
# ---------------------------------------------------------------------------

# Appended to the Briefer user message to enforce our output schema.
_BRIEFER_OUTPUT_SCHEMA = """\
Return your response as a single JSON object with this exact schema (no markdown fences):
{
  "score": <int 0-10, overall compliance rating>,
  "feedback": "<one-paragraph summary of findings>",
  "brief": {
    "scope": "<what the asset covers and its intended use>",
    "brand_issues": ["<issue description>", ...],
    "legal_issues": ["<issue description>", ...],
    "seo_issues": ["<issue description>", ...],
    "actions": ["<recommended action>", ...]
  }
}"""


async def run_pipeline(
    pdf_bytes: bytes,
    context: str,
    filename: str = "asset.pdf",
) -> AsyncGenerator[str, None]:
    """Async generator — yields ndjson progress lines then a final complete/error line.

    If Foundry is not configured (no connection string or agent IDs) the
    pipeline falls back to a stub that returns placeholder results.

    Args:
        pdf_bytes: Raw bytes of the uploaded marketing asset PDF.
        context:   Natural-language campaign context provided by the user.
        filename:  Original filename for logging.

    Yields:
        ndjson lines (str), each terminated with ``\\n``.
    """
    # Fall back to stub if Foundry is not configured
    if not settings.foundry_project_connection_string or not settings.researcher_agent_id:
        async for line in _run_stub_pipeline():
            yield line
        return

    client = _get_project_client()
    openai_client = None
    try:
        openai_client = client.get_openai_client()

        # ── Pre-process: extract text and font/colour metadata ──────────
        asset_text = _extract_text(pdf_bytes)
        font_metadata = extract_font_color_metadata(pdf_bytes)
        logger.info(
            "PDF pre-processed: %d chars text, %d font spans, %d unique fonts",
            len(asset_text),
            len(font_metadata["fonts"]),
            len(font_metadata["unique_fonts"]),
        )

        # ── Step 1 — Marketing Researcher ───────────────────────────────
        yield _progress("researcher", "running", "Retrieving brand, legal, and SEO guidelines…")

        researcher_output = await _run_agent(
            openai_client,
            settings.researcher_agent_id,
            (
                f"Asset filename: {filename}\n"
                f"Campaign context: {context}\n\n"
                "Please retrieve all relevant brand, legal, and SEO guidelines "
                "for reviewing this marketing asset."
            ),
        )
        logger.info("Researcher complete: %d chars", len(researcher_output))
        yield _progress("researcher", "done", "Guidelines loaded")

        # ── Step 2 — Marketing Auditor ──────────────────────────────────
        yield _progress("auditor", "running", "Analysing asset against guidelines…")

        # Build a compact font/colour/image summary (cap spans to avoid huge context)
        font_summary = json.dumps(
            {
                "unique_fonts": font_metadata["unique_fonts"],
                "unique_colors": font_metadata["unique_colors"],
                "metadata": font_metadata["metadata"],
                "image_count": font_metadata["image_count"],
                "images": font_metadata["images"],
                "sample_spans": font_metadata["fonts"][:50],
            },
            indent=2,
        )

        auditor_output = await _run_agent(
            openai_client,
            settings.auditor_agent_id,
            (
                "## Asset Text Content\n"
                f"{asset_text[:50_000]}\n\n"
                "## Font, Color, and Image Metadata (from PyMuPDF)\n"
                f"{font_summary}\n\n"
                "## Guidelines from Researcher\n"
                f"{researcher_output}\n\n"
                "Please audit this marketing asset against all the guidelines above."
            ),
        )
        logger.info("Auditor complete: %d chars", len(auditor_output))
        yield _progress("auditor", "done", "Audit complete")

        # ── Step 3 — Marketing Briefer ──────────────────────────────────
        yield _progress("briefer", "running", "Generating creative brief…")

        briefer_output = await _run_agent(
            openai_client,
            settings.briefer_agent_id,
            (
                "## Audit Results\n"
                f"{auditor_output}\n\n"
                f"{_BRIEFER_OUTPUT_SCHEMA}"
            ),
        )
        logger.info("Briefer complete: %d chars", len(briefer_output))
        yield _progress("briefer", "done", "Brief ready")

        # ── Parse and emit result ───────────────────────────────────────
        result = _parse_briefer_output(briefer_output)
        yield json.dumps(CompleteEvent(result=result).model_dump()) + "\n"

    except Exception as exc:
        logger.exception("Pipeline failed: %s", exc)
        yield json.dumps(ErrorEvent(message=str(exc)).model_dump()) + "\n"

    finally:
        if openai_client:
            await openai_client.close()
        await client.close()
