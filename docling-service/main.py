"""
docling_service/main.py
=======================
FastAPI microservice that wraps Docling.
Runs on port 8085.
Serves static images from PUBLIC_IMAGES_DIR under /public/images/docling/
"""
from __future__ import annotations

import hashlib
import json
import logging
import os
import tempfile
import time
import traceback
import uuid
from pathlib import Path
from typing import Optional

import httpx
from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from PIL import Image
from pydantic import BaseModel

from docling.document_converter import DocumentConverter, PdfFormatOption
from docling.datamodel.base_models import InputFormat
from docling.datamodel.pipeline_options import (
    PdfPipelineOptions,
    TableFormerMode,
)
from docling.datamodel.document import ConversionResult

# ── Try EasyOCR, fall back gracefully ────────────────────────────────────────
try:
    from docling.datamodel.pipeline_options import EasyOcrOptions
    _EASYOCR_AVAILABLE = True
except ImportError:
    _EASYOCR_AVAILABLE = False

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s – %(message)s",
)
logger = logging.getLogger(__name__)

PUBLIC_IMAGES_DIR = Path(
    os.environ.get(
        "DOCLING_IMAGES_DIR",
        "/home/franjr/ai-research/public/images/docling",
    )
)
PUBLIC_IMAGES_DIR.mkdir(parents=True, exist_ok=True)

SERVICE_BASE_URL = os.environ.get("DOCLING_SERVICE_URL", "http://localhost:8085").rstrip("/")
STATIC_URL_PATH = "/public/images/docling"

app = FastAPI(title="docling-service", version="1.0.0")
app.mount(
    STATIC_URL_PATH,
    StaticFiles(directory=str(PUBLIC_IMAGES_DIR)),
    name="docling-images",
)

logger.info("Images dir: %s | Base URL: %s", PUBLIC_IMAGES_DIR, SERVICE_BASE_URL)


# ── Request models ────────────────────────────────────────────────────────────

class ParseRequest(BaseModel):
    source: str
    output_format: str = "markdown"
    save_images: bool = True
    public_base_url: str = ""

class ImageRequest(BaseModel):
    source: str
    output_subdir: str = "docling"
    public_base_url: str = ""

class MarkdownRequest(BaseModel):
    source: str
    save_images: bool = True
    public_base_url: str = ""


# ── Helpers ───────────────────────────────────────────────────────────────────

def _safe_filename(prefix: str, suffix: str = ".png") -> str:
    clean = "".join(c if c.isalnum() or c == "_" else "_" for c in prefix)
    return f"{clean}_{int(time.time() * 1000)}_{uuid.uuid4().hex[:8]}{suffix}"


def _public_url(base: str, filename: str) -> str:
    return f"{base.rstrip('/')}{STATIC_URL_PATH}/{filename}"


def _download_to_temp(url: str) -> Path:
    headers = {"User-Agent": "docling-service/1.0"}
    with httpx.Client(follow_redirects=True, timeout=httpx.Timeout(connect=120, read=300, write=60, pool=10), headers=headers) as client:
        r = client.get(url)
        r.raise_for_status()
    ct = r.headers.get("content-type", "").split(";")[0].strip()
    ext = {"application/pdf": ".pdf", "application/vnd.openxmlformats-officedocument.wordprocessingml.document": ".docx"}.get(ct, ".bin")
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=ext)
    tmp.write(r.content)
    tmp.flush()
    tmp.close()
    return Path(tmp.name)


def _resolve_source(source: str) -> tuple[Path, bool]:
    if source.startswith("http://") or source.startswith("https://"):
        return _download_to_temp(source), True
    p = Path(source)
    if not p.exists():
        raise FileNotFoundError(f"Not found: {source}")
    return p.resolve(), False


def _build_pipeline(save_images: bool) -> PdfPipelineOptions:
    kwargs: dict = dict(
        do_ocr=True,
        do_table_structure=True,
        table_structure_options={"mode": TableFormerMode.ACCURATE, "do_cell_matching": True},
        generate_page_images=save_images,
        generate_picture_images=save_images,
    )
    if _EASYOCR_AVAILABLE:
        kwargs["ocr_options"] = EasyOcrOptions(use_gpu=False, lang=["en", "es"])
    return PdfPipelineOptions(**kwargs)


def _save_images(conv_result: ConversionResult, doc_slug: str, base_url: str) -> list[dict]:
    saved: list[dict] = []
    doc = conv_result.document
    if not hasattr(doc, "pictures") or not doc.pictures:
        return saved
    for pic in doc.pictures:
        try:
            img: Optional[Image.Image] = pic.get_image(doc)
            if img is None:
                continue
            page_no = getattr(pic.prov[0], "page_no", 0) if pic.prov else 0
            elem_type = getattr(pic, "label", "picture")
            short_hash = hashlib.md5(str(getattr(pic, "self_ref", uuid.uuid4())).encode()).hexdigest()[:8]
            fname = _safe_filename(f"{doc_slug}_p{page_no}_{elem_type}_{short_hash}")
            dest = PUBLIC_IMAGES_DIR / fname
            if img.mode not in ("RGB", "L"):
                img = img.convert("RGB")
            img.save(dest, format="PNG", optimize=True)
            saved.append({
                "filename": fname,
                "public_url": _public_url(base_url, fname),
                "page": page_no,
                "type": str(elem_type),
                "width": img.width,
                "height": img.height,
                "size_bytes": dest.stat().st_size,
            })
        except Exception as e:
            logger.warning("Image save failed: %s", e)
    return saved


def _converter(save_images: bool) -> DocumentConverter:
    return DocumentConverter(
        format_options={InputFormat.PDF: PdfFormatOption(pipeline_options=_build_pipeline(save_images))}
    )


# ── Routes ────────────────────────────────────────────────────────────────────

@app.get("/health")
def health():
    return {"status": "ok", "easyocr": _EASYOCR_AVAILABLE}


@app.post("/parse")
def parse_document(req: ParseRequest) -> dict:
    base_url = req.public_base_url.strip() or SERVICE_BASE_URL
    is_temp = False
    path = None
    try:
        path, is_temp = _resolve_source(req.source)
        slug = path.stem[:20].replace(" ", "_").lower()
        conv = _converter(req.save_images).convert(str(path))
        if req.output_format.lower() == "json":
            content = json.dumps(conv.document.export_to_dict(), ensure_ascii=False, default=str)
        else:
            content = conv.document.export_to_markdown()
        images = _save_images(conv, slug, base_url) if req.save_images else []
        page_count = len(conv.document.pages) if hasattr(conv.document, "pages") else 0
        return {"status": "success", "source": req.source, "output_format": req.output_format,
                "content": content, "page_count": page_count, "images": images, "image_count": len(images)}
    except Exception as e:
        return {"status": "error", "source": req.source, "error": str(e), "traceback": traceback.format_exc()}
    finally:
        if is_temp and path:
            path.unlink(missing_ok=True)


@app.post("/extract-images")
def extract_images(req: ImageRequest) -> dict:
    base_url = req.public_base_url.strip() or SERVICE_BASE_URL
    is_temp = False
    path = None
    try:
        path, is_temp = _resolve_source(req.source)
        slug = req.output_subdir[:15].replace(" ", "_").lower()
        conv = _converter(True).convert(str(path))
        images = _save_images(conv, slug, base_url)
        return {"status": "success", "source": req.source, "image_count": len(images), "images": images}
    except Exception as e:
        return {"status": "error", "source": req.source, "error": str(e), "traceback": traceback.format_exc()}
    finally:
        if is_temp and path:
            path.unlink(missing_ok=True)


@app.post("/to-markdown")
def to_markdown(req: MarkdownRequest) -> dict:
    base_url = req.public_base_url.strip() or SERVICE_BASE_URL
    is_temp = False
    path = None
    try:
        path, is_temp = _resolve_source(req.source)
        slug = path.stem[:20].replace(" ", "_").lower()
        conv = _converter(req.save_images).convert(str(path))
        md = conv.document.export_to_markdown()
        images = _save_images(conv, slug, base_url) if req.save_images else []
        return {"status": "success", "source": req.source, "markdown": md,
                "images": images, "char_count": len(md), "image_count": len(images)}
    except Exception as e:
        return {"status": "error", "source": req.source, "error": str(e), "traceback": traceback.format_exc()}
    finally:
        if is_temp and path:
            path.unlink(missing_ok=True)
