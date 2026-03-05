"""Load synthetic brand guidelines into the brandsense-guidelines AI Search index.

Run once to seed the knowledge base used by the Marketing Researcher agent.
Re-run whenever guidelines change.

Usage:
    python scripts/load/guidelines.py

Prerequisites:
    - Environment variables (or .env file):
        AZURE_SEARCH_ENDPOINT   : https://<name>.search.windows.net
        AZURE_OPENAI_ENDPOINT   : https://<name>.cognitiveservices.azure.com/
    - Azure credentials available (az login or managed identity)
    - pip install -r scripts/load/requirements.txt
"""

import json
import logging
import os
from pathlib import Path

from azure.identity import DefaultAzureCredential, get_bearer_token_provider
from azure.search.documents import SearchClient
from azure.search.documents.indexes import SearchIndexClient
from azure.search.documents.indexes.models import (
    AzureOpenAIVectorizer,
    AzureOpenAIParameters,
    HnswAlgorithmConfiguration,
    SearchField,
    SearchFieldDataType,
    SearchIndex,
    SemanticConfiguration,
    SemanticField,
    SemanticPrioritizedFields,
    SemanticSearch,
    SimpleField,
    SearchableField,
    VectorSearch,
    VectorSearchProfile,
)
from dotenv import load_dotenv
from openai import AzureOpenAI

load_dotenv()

logging.basicConfig(level=logging.INFO, format="[%(levelname)s] %(message)s")
logger = logging.getLogger(__name__)

INDEX_NAME = os.getenv("AZURE_SEARCH_INDEX_NAME", "brandsense-guidelines")
SEARCH_ENDPOINT = os.getenv("AZURE_SEARCH_ENDPOINT", "")
OPENAI_ENDPOINT = os.getenv("AZURE_OPENAI_ENDPOINT", "")
EMBEDDING_DEPLOYMENT = os.getenv("AZURE_OPENAI_EMBEDDING_DEPLOYMENT", "text-embedding-ada-002")
EMBEDDING_DIMENSIONS = 1536
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
        # Vector field — pre-computed from text-embedding-ada-002
        SearchField(
            name="content_vector",
            type=SearchFieldDataType.Collection(SearchFieldDataType.Single),
            searchable=True,
            vector_search_dimensions=EMBEDDING_DIMENSIONS,
            vector_search_profile_name="hnsw-profile",
        ),
    ]

    # Integrated vectorizer: the search service calls Azure OpenAI directly to embed
    # queries at search time using its system-assigned managed identity.
    # This is required for Foundry's vector_semantic_hybrid agent search tool.
    vectorizer = AzureOpenAIVectorizer(
        name="ada-002-vectorizer",
        azure_open_ai_parameters=AzureOpenAIParameters(
            resource_uri=OPENAI_ENDPOINT.rstrip("/"),
            deployment_id=EMBEDDING_DEPLOYMENT,
            model_name=EMBEDDING_DEPLOYMENT,
        ),
    )

    vector_search = VectorSearch(
        algorithms=[HnswAlgorithmConfiguration(name="hnsw-config")],
        profiles=[VectorSearchProfile(
            name="hnsw-profile",
            algorithm_configuration_name="hnsw-config",
            vectorizer="ada-002-vectorizer",
        )],
        vectorizers=[vectorizer],
    )

    semantic_search = SemanticSearch(
        configurations=[
            SemanticConfiguration(
                name="brandsense-semantic",
                prioritized_fields=SemanticPrioritizedFields(
                    content_fields=[
                        SemanticField(field_name="description"),
                        SemanticField(field_name="value"),
                    ],
                    keywords_fields=[
                        SemanticField(field_name="rule"),
                        SemanticField(field_name="category"),
                    ],
                ),
            )
        ]
    )

    return SearchIndex(
        name=INDEX_NAME,
        fields=fields,
        vector_search=vector_search,
        semantic_search=semantic_search,
    )


def build_embed_text(doc: dict) -> str:
    """Concatenate the most informative fields into a single string to embed."""
    parts = [
        doc.get("category", ""),
        doc.get("rule", ""),
        doc.get("value", ""),
        doc.get("description", ""),
    ]
    return " | ".join(p for p in parts if p)


def generate_embeddings(openai_client: AzureOpenAI, texts: list[str]) -> list[list[float]]:
    """Call text-embedding-ada-002 in batches of 100 and return embeddings."""
    embeddings: list[list[float]] = []
    batch_size = 100
    for i in range(0, len(texts), batch_size):
        batch = texts[i : i + batch_size]
        logger.info("Embedding batch %d-%d of %d...", i + 1, i + len(batch), len(texts))
        response = openai_client.embeddings.create(
            input=batch,
            model=EMBEDDING_DEPLOYMENT,
        )
        embeddings.extend(item.embedding for item in response.data)
    return embeddings


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
    if not OPENAI_ENDPOINT:
        raise ValueError("AZURE_OPENAI_ENDPOINT is not set. Check your .env file.")

    credential = DefaultAzureCredential()
    token_provider = get_bearer_token_provider(credential, "https://cognitiveservices.azure.com/.default")

    openai_client = AzureOpenAI(
        azure_endpoint=OPENAI_ENDPOINT,
        azure_ad_token_provider=token_provider,
        api_version="2024-02-01",
    )

    index_client = SearchIndexClient(endpoint=SEARCH_ENDPOINT, credential=credential)

    logger.info("Creating/updating index '%s'...", INDEX_NAME)
    index_client.create_or_update_index(get_index_definition())
    logger.info("Index ready.")

    documents = load_documents()
    if not documents:
        logger.error("No documents to upload. Exiting.")
        return

    # Generate embeddings for all documents
    texts = [build_embed_text(doc) for doc in documents]
    embeddings = generate_embeddings(openai_client, texts)
    for doc, embedding in zip(documents, embeddings):
        doc["content_vector"] = embedding

    search_client = SearchClient(
        endpoint=SEARCH_ENDPOINT,
        index_name=INDEX_NAME,
        credential=credential,
    )

    logger.info("Uploading %d documents with embeddings to index...", len(documents))
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
