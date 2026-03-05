"""BrandSense API — Pydantic models.

Agent communication contracts shared across the three-agent pipeline:
  Marketing Researcher → Marketing Auditor → Marketing Briefer
"""

from __future__ import annotations

from typing import Optional

from pydantic import BaseModel, Field


# ---------------------------------------------------------------------------
# Marketing Researcher output
# ---------------------------------------------------------------------------

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


# ---------------------------------------------------------------------------
# Marketing Auditor output
# ---------------------------------------------------------------------------

class Check(BaseModel):
    rule: str
    passed: bool  # 'pass' is a Python keyword
    issue: Optional[str] = None
    page_refs: Optional[list[int]] = None


class AuditorOutput(BaseModel):
    brand_checks: list[Check]
    legal_checks: list[Check]
    seo_checks: list[Check]
    overall_pass: bool


# ---------------------------------------------------------------------------
# Marketing Briefer output
# ---------------------------------------------------------------------------

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


# ---------------------------------------------------------------------------
# API response models
# ---------------------------------------------------------------------------

class HealthResponse(BaseModel):
    status: str
    service: str = "brandsense-api"
    foundry_configured: bool
    document_intelligence_configured: bool
    search_configured: bool


# ---------------------------------------------------------------------------
# Streaming pipeline events (ndjson lines emitted by POST /validate)
# ---------------------------------------------------------------------------

class ProgressEvent(BaseModel):
    """Emitted by the pipeline as each agent starts or finishes."""
    event: str = "progress"
    agent: str              # "researcher" | "auditor" | "briefer"
    status: str             # "running" | "done" | "error"
    message: str


class CompleteEvent(BaseModel):
    """Final line of the stream — carries the full BrieferOutput result."""
    event: str = "complete"
    result: BrieferOutput


class ErrorEvent(BaseModel):
    """Emitted if the pipeline fails before producing a result."""
    event: str = "error"
    message: str
