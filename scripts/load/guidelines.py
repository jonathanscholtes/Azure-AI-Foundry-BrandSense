"""Load synthetic brand guidelines into the brandsense-guidelines AI Search index.

Run once to seed the knowledge base used by the Marketing Researcher agent.
Re-run whenever guidelines change.

Usage:
    python scripts/load/guidelines.py

Prerequisites:
    - .env file with AZURE_SEARCH_ENDPOINT set (or env var)
    - Azure credentials available (az login or managed identity)
    - pip install -r scripts/load/requirements.txt
"""

import json
import logging
import os
from pathlib import Path

from azure.identity import DefaultAzureCredential
from azure.search.documents import SearchClient
from azure.search.documents.indexes import SearchIndexClient
from azure.search.documents.indexes.models import (
    SearchIndex,
    SearchFieldDataType,
    SimpleField,
    SearchableField,
)
from dotenv import load_dotenv

load_dotenv()

logging.basicConfig(level=logging.INFO, format="[%(levelname)s] %(message)s")
logger = logging.getLogger(__name__)

INDEX_NAME = os.getenv("AZURE_SEARCH_INDEX_NAME", "brandsense-guidelines")
SEARCH_ENDPOINT = os.getenv("AZURE_SEARCH_ENDPOINT", "")
GUIDELINES_DIR = Path(__file__).parent / "data"


def get_index_definition() -> SearchIndex:
    fields = [
        SimpleField(name="id", type=SearchFieldDataType.String, key=True, filterable=True),
        SimpleField(name="category", type=SearchFieldDataType.String, filterable=True, facetable=True),
        SearchableField(name="rule", type=SearchFieldDataType.String),
        SearchableField(name="value", type=SearchFieldDataType.String),
        SimpleField(name="jurisdiction", type=SearchFieldDataType.String, filterable=True, facetable=True),
        SimpleField(name="dimension", type=SearchFieldDataType.String, filterable=True, facetable=True),
        SearchableField(name="description", type=SearchFieldDataType.String),
    ]
    return SearchIndex(name=INDEX_NAME, fields=fields)


def load_documents() -> list[dict]:
    documents = []
    for category_file in ["brand.json", "legal.json", "seo.json"]:
        path = GUIDELINES_DIR / category_file
        if not path.exists():
            logger.warning("Guideline file not found: %s", path)
            continue
        with open(path, encoding="utf-8") as f:
            items = json.load(f)
        documents.extend(items)
        logger.info("Loaded %d documents from %s", len(items), category_file)
    return documents


def main():
    if not SEARCH_ENDPOINT:
        raise ValueError("AZURE_SEARCH_ENDPOINT is not set. Check your .env file.")

    credential = DefaultAzureCredential()
    index_client = SearchIndexClient(endpoint=SEARCH_ENDPOINT, credential=credential)

    logger.info("Creating/updating index '%s'...", INDEX_NAME)
    index_client.create_or_update_index(get_index_definition())
    logger.info("Index ready.")

    documents = load_documents()
    if not documents:
        logger.error("No documents to upload. Exiting.")
        return

    search_client = SearchClient(
        endpoint=SEARCH_ENDPOINT,
        index_name=INDEX_NAME,
        credential=credential,
    )

    logger.info("Uploading %d documents to index...", len(documents))
    result = search_client.upload_documents(documents=documents)
    succeeded = sum(1 for r in result if r.succeeded)
    failed = len(result) - succeeded
    logger.info("Upload complete: %d succeeded, %d failed.", succeeded, failed)
    if failed:
        for r in result:
            if not r.succeeded:
                logger.error("Failed to upload doc id=%s: %s", r.key, r.error_message)


if __name__ == "__main__":
    main()
