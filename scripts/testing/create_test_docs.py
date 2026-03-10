"""
Generate BrandSense test PDFs.

Produces five PDFs that exercise distinct audit outcomes so you can verify
the pipeline grades documents correctly before running real assets.

Usage:
    python scripts/testing/create_test_docs.py [--out-dir <path>]

    Defaults to  scripts/testing/docs/

Documents generated
-------------------
1. compliant.pdf          — All rules satisfied. Expected grade: A (9-10)
2. wrong_fonts_colors.pdf — Calibri + Cambria, off-brand blues. Expected grade: B-C
3. no_logo.pdf            — No images at all. Expected grade: D-F (brand-016 error)
4. no_copyright.pdf       — Good fonts/colours/logo, but no © notice. Expected grade: C-D
5. multiple_failures.pdf  — Wrong fonts, no logo, no copyright. Expected grade: F
"""

import argparse
import os
from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import inch, mm
from reportlab.pdfgen import canvas
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont

# ---------------------------------------------------------------------------
# Brand constants (from brand.json)
# ---------------------------------------------------------------------------
BRAND_BLUE      = colors.HexColor("#0078D4")
BRAND_CYAN      = colors.HexColor("#50E6FF")
OFF_BLUE_1      = colors.HexColor("#4F81BD")   # non-compliant (Office theme)
OFF_BLUE_2      = colors.HexColor("#365F91")   # non-compliant (Office theme)
BLACK           = colors.HexColor("#000000")
WHITE           = colors.HexColor("#FFFFFF")
LIGHT_GREY      = colors.HexColor("#F3F3F3")

APPROVED_FONT   = "Helvetica"        # Arial/Helvetica — approved fallback
PROHIBITED_FONT_BOLD = "Helvetica-Bold"

# ReportLab built-ins that approximate brand-compliant and prohibited faces:
#   Helvetica  ≈ Arial (approved fallback per brand-005)
#   Times-Roman is prohibited (like Times New Roman) — used in failing docs
COMPLIANT_BODY  = "Helvetica"
COMPLIANT_HEAD  = "Helvetica-Bold"
PROHIBITED_BODY = "Times-Roman"       # brand-006 violation
PROHIBITED_HEAD = "Times-Bold"

COPYRIGHT = "© 2026 Microsoft Corporation. All rights reserved."

LOREM = (
    "This marketing asset presents the latest campaign initiatives for the "
    "Azure AI platform, targeting enterprise customers across EMEA and North America. "
    "The document outlines key messaging, brand positioning, and call-to-action "
    "strategies aligned with Q2 objectives. All imagery, copy, and design elements "
    "must comply with brand, legal, and SEO guidelines before external publication."
)

BODY_COPY = (
    "Azure AI provides intelligent cloud services that help organisations build, "
    "deploy, and manage AI solutions at scale. Our platform delivers reliable, "
    "secure, and responsible AI capabilities — enabling teams to move from "
    "prototype to production faster than ever before. "
    "Contact your Microsoft account team to learn more."
)


# ---------------------------------------------------------------------------
# Drawing helpers
# ---------------------------------------------------------------------------

def _header(c: canvas.Canvas, title: str, font: str, head_color, bg_color=BRAND_BLUE):
    """Draw a full-width header bar with title text."""
    w, h = A4
    c.setFillColor(bg_color)
    c.rect(0, h - 72, w, 72, fill=1, stroke=0)
    c.setFillColor(WHITE)
    c.setFont(font, 22)
    c.drawString(24, h - 48, title)


def _logo_placeholder(c: canvas.Canvas, x, y, width=120, height=40, color=BRAND_BLUE):
    """Draw a coloured rectangle as a stand-in for the real brand logo."""
    c.setFillColor(color)
    c.rect(x, y, width, height, fill=1, stroke=0)
    c.setFillColor(WHITE)
    c.setFont("Helvetica-Bold", 14)
    c.drawString(x + 10, y + 12, "LOGO")


def _body(c: canvas.Canvas, text: str, font: str, color, y_start: float) -> float:
    """Draw wrapped body text; returns the y position after last line."""
    w, _ = A4
    c.setFillColor(color)
    c.setFont(font, 11)
    margin = 48
    text_width = w - 2 * margin
    # Simple word-wrap
    words = text.split()
    line, lines = [], []
    for word in words:
        trial = " ".join(line + [word])
        if c.stringWidth(trial, font, 11) <= text_width:
            line.append(word)
        else:
            lines.append(" ".join(line))
            line = [word]
    if line:
        lines.append(" ".join(line))

    y = y_start
    for ln in lines:
        c.drawString(margin, y, ln)
        y -= 16
    return y


def _footer(c: canvas.Canvas, text: str, font: str = "Helvetica", size: int = 8):
    """Draw footer text at the bottom of the page."""
    c.setFillColor(BLACK)
    c.setFont(font, size)
    c.drawString(48, 20, text)


def _section_heading(c: canvas.Canvas, text: str, font: str, color, y: float) -> float:
    c.setFillColor(color)
    c.setFont(font, 14)
    c.drawString(48, y, text)
    return y - 24


# ---------------------------------------------------------------------------
# Document builders
# ---------------------------------------------------------------------------

def make_compliant(path: Path):
    """
    PASS document — satisfies every auditable rule.

    Font     : Helvetica / Helvetica-Bold  (Arial-equivalent, brand-005 approved fallback)
    Colours  : #0078D4 header, #000000 body (brand-001 primary blue)
    Logo     : Rectangle placeholder image present (brand-016)
    Copyright: Present in footer (legal-001)
    Trademark: Microsoft® on first use (legal-002)
    """
    c = canvas.Canvas(str(path), pagesize=A4)
    w, h = A4

    # Page 1
    _header(c, "Azure AI Platform — Campaign Asset", COMPLIANT_HEAD, WHITE, BRAND_BLUE)
    _logo_placeholder(c, 48, h - 68)

    y = h - 110
    y = _section_heading(c, "Overview", COMPLIANT_HEAD, BRAND_BLUE, y)
    y = _body(c, BODY_COPY, COMPLIANT_BODY, BLACK, y) - 12

    y = _section_heading(c, "Campaign Objectives", COMPLIANT_HEAD, BRAND_BLUE, y)
    y = _body(c, LOREM, COMPLIANT_BODY, BLACK, y) - 12

    y = _section_heading(c, "Key Messages", COMPLIANT_HEAD, BRAND_BLUE, y)
    y = _body(
        c,
        "Microsoft® Azure delivers enterprise-grade AI at scale. "
        "Our solutions are built on a foundation of security, compliance, and reliability. "
        "Azure AI Studio enables teams to build and deploy custom AI models with confidence.",
        COMPLIANT_BODY, BLACK, y,
    )

    _footer(c, COPYRIGHT)
    c.showPage()

    # Page 2
    _header(c, "Azure AI Platform — Campaign Asset", COMPLIANT_HEAD, WHITE, BRAND_BLUE)
    _logo_placeholder(c, 48, h - 68)
    y = h - 110
    y = _section_heading(c, "Next Steps", COMPLIANT_HEAD, BRAND_BLUE, y)
    y = _body(c, "Contact your Microsoft account team to schedule a briefing.", COMPLIANT_BODY, BLACK, y)
    _footer(c, COPYRIGHT)
    c.showPage()

    c.save()
    print(f"  Created: {path}")


def make_wrong_fonts_colors(path: Path):
    """
    PARTIAL FAIL — wrong typeface + off-brand colour palette.
    Mirrors Evaluation_Summary_V2.pdf characteristics.

    Font  : Times-Roman / Times-Bold  (brand-006 violation — prohibited serif)
    Color : #4F81BD, #365F91           (brand-001 violation — not #0078D4)
    Logo  : Present                    (brand-016 pass)
    Copyright: Present                 (legal-001 pass)
    Expected grade: B-C
    """
    c = canvas.Canvas(str(path), pagesize=A4)
    w, h = A4

    _header(c, "Q2 Campaign Brief", PROHIBITED_HEAD, WHITE, OFF_BLUE_1)
    _logo_placeholder(c, 48, h - 68, color=OFF_BLUE_2)

    y = h - 110
    c.setFillColor(OFF_BLUE_2)
    c.setFont(PROHIBITED_HEAD, 14)
    c.drawString(48, y, "Campaign Summary")
    y -= 24

    y = _body(c, BODY_COPY, PROHIBITED_BODY, BLACK, y) - 12

    c.setFillColor(OFF_BLUE_1)
    c.setFont(PROHIBITED_HEAD, 14)
    c.drawString(48, y, "Objectives")
    y -= 24
    y = _body(c, LOREM, PROHIBITED_BODY, BLACK, y)

    _footer(c, COPYRIGHT, font="Times-Roman")
    c.showPage()
    c.save()
    print(f"  Created: {path}")


def make_no_logo(path: Path):
    """
    FAIL — no images anywhere in the document.

    Font  : Helvetica (compliant)
    Color : #0078D4   (compliant)
    Logo  : ABSENT    (brand-016 error)
    Copyright: Present (legal-001 pass)
    Expected grade: D-F
    """
    c = canvas.Canvas(str(path), pagesize=A4)
    w, h = A4

    # Header bar — no logo drawn
    c.setFillColor(BRAND_BLUE)
    c.rect(0, h - 72, w, 72, fill=1, stroke=0)
    c.setFillColor(WHITE)
    c.setFont(COMPLIANT_HEAD, 22)
    c.drawString(24, h - 48, "Azure AI — Internal Evaluation Report")

    y = h - 110
    y = _section_heading(c, "Evaluation Findings", COMPLIANT_HEAD, BRAND_BLUE, y)
    y = _body(c, BODY_COPY, COMPLIANT_BODY, BLACK, y) - 12
    y = _section_heading(c, "Recommendations", COMPLIANT_HEAD, BRAND_BLUE, y)
    y = _body(c, LOREM, COMPLIANT_BODY, BLACK, y)

    _footer(c, COPYRIGHT)
    c.showPage()
    c.save()
    print(f"  Created: {path}")


def make_no_copyright(path: Path):
    """
    FAIL — missing copyright notice.

    Font  : Helvetica (compliant)
    Color : #0078D4   (compliant)
    Logo  : Present   (brand-016 pass)
    Copyright: ABSENT (legal-001 error)
    Expected grade: C-D
    """
    c = canvas.Canvas(str(path), pagesize=A4)
    w, h = A4

    _header(c, "Azure AI — Partner Datasheet", COMPLIANT_HEAD, WHITE, BRAND_BLUE)
    _logo_placeholder(c, 48, h - 68)

    y = h - 110
    y = _section_heading(c, "Solution Overview", COMPLIANT_HEAD, BRAND_BLUE, y)
    y = _body(c, BODY_COPY, COMPLIANT_BODY, BLACK, y) - 12
    y = _section_heading(c, "Key Benefits", COMPLIANT_HEAD, BRAND_BLUE, y)
    y = _body(c, LOREM, COMPLIANT_BODY, BLACK, y)

    # ← No copyright footer drawn
    c.showPage()
    c.save()
    print(f"  Created: {path}")


def make_multiple_failures(path: Path):
    """
    FAIL — stacks wrong fonts, no logo, and no copyright.

    Font  : Times-Roman (brand-006 violation)
    Color : #4F81BD     (brand-001 violation)
    Logo  : ABSENT      (brand-016 error)
    Copyright: ABSENT   (legal-001 error)
    Expected grade: F
    """
    c = canvas.Canvas(str(path), pagesize=A4)
    w, h = A4

    # Header with off-brand colour, no logo
    c.setFillColor(OFF_BLUE_1)
    c.rect(0, h - 72, w, 72, fill=1, stroke=0)
    c.setFillColor(WHITE)
    c.setFont(PROHIBITED_HEAD, 22)
    c.drawString(24, h - 48, "Global Evaluation Summary")

    y = h - 110
    c.setFillColor(OFF_BLUE_2)
    c.setFont(PROHIBITED_HEAD, 14)
    c.drawString(48, y, "Common Failure Patterns")
    y -= 24

    y = _body(c, BODY_COPY, PROHIBITED_BODY, BLACK, y) - 12

    c.setFillColor(OFF_BLUE_1)
    c.setFont(PROHIBITED_HEAD, 14)
    c.drawString(48, y, "Systemic Issues")
    y -= 24
    y = _body(c, LOREM, PROHIBITED_BODY, BLACK, y)

    # ← No copyright footer, no logo
    c.showPage()
    c.save()
    print(f"  Created: {path}")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

DOCS = [
    ("compliant.pdf",           make_compliant,           "All rules satisfied — expected A"),
    ("wrong_fonts_colors.pdf",  make_wrong_fonts_colors,  "Wrong font + off-brand colours — expected B-C"),
    ("no_logo.pdf",             make_no_logo,             "No logo/images — expected D-F"),
    ("no_copyright.pdf",        make_no_copyright,        "Missing copyright notice — expected C-D"),
    ("multiple_failures.pdf",   make_multiple_failures,   "Wrong font + no logo + no copyright — expected F"),
]


def main():
    parser = argparse.ArgumentParser(description="Generate BrandSense test PDFs.")
    parser.add_argument(
        "--out-dir",
        default=str(Path(__file__).parent / "docs"),
        help="Directory to write PDFs into (default: scripts/testing/docs/)",
    )
    args = parser.parse_args()

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    print(f"Writing test documents to: {out_dir.resolve()}\n")
    for filename, builder, description in DOCS:
        print(f"[{description}]")
        builder(out_dir / filename)

    print(f"\nDone — {len(DOCS)} documents written.")


if __name__ == "__main__":
    main()
