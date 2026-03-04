"""BrandSense agent pipeline.

Orchestrates the three-agent sequential workflow via the Foundry Workflow API:
  1. Marketing Researcher  — retrieves brand/legal/SEO requirements from AI Search
  2. Marketing Auditor     — checks the asset against those requirements (uses PyMuPDF via APIM MCP)
  3. Marketing Briefer     — synthesises findings into a scored brief

TODO (M5): Replace stubs with actual Foundry Workflow API calls once
           all three agents are deployed to Foundry (M2–M4).
"""

from models import BrieferOutput


async def run_pipeline(pdf_bytes: bytes, context: str) -> BrieferOutput:
    """Trigger the Researcher → Auditor → Briefer pipeline.

    Args:
        pdf_bytes: Raw bytes of the uploaded marketing asset PDF.
        context:   Natural-language campaign context provided by the user.

    Returns:
        BrieferOutput with score (0–10), feedback, and detailed brief.
    """
    # --- M2: Marketing Researcher ---
    # researcher_output = await _run_researcher(context)

    # --- M3: Marketing Auditor ---
    # auditor_output = await _run_auditor(pdf_bytes, researcher_output)

    # --- M4: Marketing Briefer ---
    # return await _run_briefer(auditor_output)

    raise NotImplementedError(
        "Pipeline not yet implemented. "
        "Implement agents in M2–M4 then wire them here in M5."
    )
