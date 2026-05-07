"""
docling_actions.py
==================
Sema4.ai Action Package – docling-tools

Thin HTTP wrappers over the local docling-service (FastAPI, port 8085).
Zero ML dependencies in this environment.
"""
from __future__ import annotations

import json
import logging
import os

import httpx
from sema4ai.actions import action

logger = logging.getLogger(__name__)
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s – %(message)s",
)

DOCLING_SERVICE_URL = os.environ.get(
    "DOCLING_SERVICE_URL", "http://localhost:8085"
).rstrip("/")

_TIMEOUT = httpx.Timeout(connect=10.0, read=600.0, write=30.0, pool=5.0)


def _post(endpoint: str, payload: dict) -> str:
    try:
        with httpx.Client(timeout=_TIMEOUT) as client:
            r = client.post(f"{DOCLING_SERVICE_URL}{endpoint}", json=payload)
            r.raise_for_status()
            return r.text
    except Exception as exc:
        return json.dumps({"status": "error", "error": str(exc)})


@action(is_consequential=True)
def parse_document(
    source: str,
    output_format: str = "markdown",
    save_images: bool = True,
    public_base_url: str = "",
) -> str:
    """Parse a PDF or document with Docling OCR and return full structured content.

    Args:
        source: HTTP/HTTPS URL or absolute local file path.
        output_format: 'markdown' (default) or 'json'.
        save_images: Extract and save images when True.
        public_base_url: Root URL for image URLs. Defaults to docling-service base.

    Returns:
        JSON string with status, content, page_count, images, image_count.
    """
    return _post("/parse", {
        "source": source,
        "output_format": output_format,
        "save_images": save_images,
        "public_base_url": public_base_url,
    })


@action(is_consequential=True)
def extract_and_save_images(
    source: str,
    output_subdir: str = "docling",
    public_base_url: str = "",
) -> str:
    """Extract and persist every image in a document, returning public URLs.

    Args:
        source: HTTP/HTTPS URL or absolute local file path.
        output_subdir: Filename prefix for organization.
        public_base_url: Root URL for image URLs.

    Returns:
        JSON string with status, source, image_count, images array.
    """
    return _post("/extract-images", {
        "source": source,
        "output_subdir": output_subdir,
        "public_base_url": public_base_url,
    })


@action
def convert_to_markdown(
    source: str,
    save_images: bool = True,
    public_base_url: str = "",
) -> str:
    """Convert a document to clean Markdown with optional image extraction.

    Args:
        source: HTTP/HTTPS URL or absolute local path.
        save_images: Extract images and include URLs when True.
        public_base_url: Root URL for image URLs.

    Returns:
        JSON string with status, markdown, images, char_count, image_count.
    """
    return _post("/to-markdown", {
        "source": source,
        "save_images": save_images,
        "public_base_url": public_base_url,
    })
