"""BrandSense API — FastAPI application.

Endpoints:
  POST /validate              — triggers the Foundry agent pipeline, returns BrieferOutput
  POST /tools/extract-fonts   — PyMuPDF tool endpoint; exposed as MCP tool via APIM
  GET  /health                — liveness probe (Container Apps + GitHub Actions)
  GET  /                      — serves the React SPA static files (production)
"""

import logging
import uvicorn
from contextlib import asynccontextmanager

from fastapi import FastAPI, UploadFile, Form, HTTPException
from fastapi.staticfiles import StaticFiles

from config import settings
from models import BrieferOutput, HealthResponse
from tools.pymupdf import extract_font_color_metadata
from workflow.pipeline import run_pipeline


logging.basicConfig(
    level=settings.log_level,
    format="[%(asctime)s] %(levelname)-8s - %(name)s - %(message)s",
)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info(
        "BrandSense API starting — environment=%s foundry_configured=%s",
        settings.environment,
        bool(settings.foundry_project_connection_string),
    )
    yield
    logger.info("BrandSense API shutting down")


app = FastAPI(
    title="BrandSense API",
    description=(
        "Marketing asset validation API. "
        "Exposed as an MCP Server via APIM for Foundry agent tool discovery."
    ),
    version="0.1.0",
    lifespan=lifespan,
)


@app.get("/health", response_model=HealthResponse)
def health():
    """Liveness probe used by Container Apps and GitHub Actions deploy workflow."""
    return HealthResponse(
        status="ok",
        foundry_configured=bool(settings.foundry_project_connection_string),
        document_intelligence_configured=bool(settings.azure_document_intelligence_endpoint),
        search_configured=bool(settings.azure_search_endpoint),
    )


@app.post("/validate", response_model=BrieferOutput)
async def validate(file: UploadFile, context: str = Form(...)):
    """Validate a marketing asset PDF.

    Triggers the Foundry Researcher → Auditor → Briefer pipeline and returns
    a scored, structured validation report.
    """
    if not settings.foundry_project_connection_string:
        raise HTTPException(status_code=503, detail="Foundry project connection string not configured")

    pdf_bytes = await file.read()
    logger.info("Received validation request: filename=%s context=%.80s", file.filename, context)

    result = await run_pipeline(pdf_bytes=pdf_bytes, context=context)
    logger.info("Validation complete: score=%s overall_pass=%s", result.score, result.brief)
    return result


@app.post("/tools/extract-fonts")
async def extract_fonts(file: UploadFile):
    """Extract exact font families, sizes, and colour values from a PDF.

    Exposed as an MCP tool via APIM — called automatically by the
    Foundry Marketing Auditor agent during brand compliance checks.
    """
    pdf_bytes = await file.read()
    logger.info("extract-fonts called: filename=%s size=%d bytes", file.filename, len(pdf_bytes))
    return extract_font_color_metadata(pdf_bytes)


# Serve the built React SPA (apps/ui/dist/) in production.
# Must be mounted last so FastAPI routes take precedence.
try:
    app.mount("/", StaticFiles(directory="apps/ui/dist", html=True), name="ui")
except RuntimeError:
    # apps/ui/dist not present — API still works in local dev and CI
    pass


if __name__ == "__main__":
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=settings.port,
        log_level=settings.log_level.lower(),
    )
