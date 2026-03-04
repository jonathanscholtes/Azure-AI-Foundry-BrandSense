"""PyMuPDF extraction tool.

Called by the FastAPI /tools/extract-fonts endpoint, which is exposed to
the Foundry Marketing Auditor agent via the APIM MCP Server.
"""

import fitz  # PyMuPDF


def extract_font_color_metadata(pdf_bytes: bytes) -> dict:
    """Extract exact font families, sizes, and colour values from every page of a PDF.

    Returns a dict containing:
    - fonts: list of per-span entries with font name, size, colour (hex), and page number
    - unique_fonts: deduplicated set of font names used in the document
    - unique_colors: deduplicated set of colour values used in the document
    - metadata: PDF document metadata (title, author, subject, etc.)
    """
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
