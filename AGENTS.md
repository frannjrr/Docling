# Agent Manual — Docling Project

## Identity
This is a production-grade document processing stack composed of two coordinated services:
- **docling-service**: FastAPI ML microservice (port 8085). Handles OCR, parsing, image extraction, and Markdown conversion using Docling + EasyOCR.
- **docling-tools**: Sema4.ai Action Server (port 8082). Thin HTTP wrappers that expose Docling capabilities as AI actions via MCP and OpenAPI.

## Architecture
```
Agent → MCP/OpenAPI → docling-tools (:8082) → HTTP → docling-service (:8085) → [Docling + EasyOCR]
```

## Available Agent Actions (via Action Server)

### 1. `parse_document`
Full document parse with OCR + image extraction.
- **Args**: `source` (URL or local path), `output_format` ("markdown"|""json"), `save_images` (bool), `public_base_url` (str)
- **Returns**: JSON with `status`, `content`, `page_count`, `images`, `image_count`

### 2. `extract_and_save_images`
Image-only extraction.
- **Args**: `source`, `output_subdir`, `public_base_url`
- **Returns**: JSON with `status`, `source`, `image_count`, `images`

### 3. `convert_to_markdown`
Fast text-only conversion to Markdown.
- **Args**: `source`, `save_images`, `public_base_url`
- **Returns**: JSON with `status`, `markdown`, `images`, `char_count`, `image_count`

## Runtime Requirements (Self-Check)
Before invoking any action, verify:
1. docling-service is running: `curl -s http://localhost:8085/health`
   Expected: `{"status": "ok", "easyocr": true}`
2. Action Server is running: `curl -s http://localhost:8082/openapi.json | grep "parse_document"`
3. If health check fails, warn the user and DO NOT attempt processing.

## Configuration
| Variable | Default | Description |
|----------|---------|-------------|
| `DOCLING_SERVICE_URL` | `http://localhost:8085` | Backend service URL used by actions |
| `DOCLING_IMAGES_DIR` | `/home/franjr/ai-research/public/images/docling` | Where extracted images are stored and served |

## Common Failure Modes
- "Connection refused" on port 8085 → docling-service is not running. Start: `cd ~/docling-service && ./start.sh`
- "Connection refused" on port 8082 → Action Server is not running. Start: `cd ~/ai-research/docling-tools && action-server start --port 8082`
- EasyOCR models not found → first run downloads ~50MB automatically. Wait for completion.
- Timeout on large PDFs → read timeout is set to 600s. May need retries for very large documents.

## Context Refresh
To update this manual with the current state of the codebase, run:
```bash
.bash .agent/update-context.sh
```
This will regenerate `AGENTS.md` with current file contents, dependencies, and endpoint status.

## Self-Improvement Protocol
1. After each document processing task, note any errors or edge cases encountered.
2. If a pattern is identified (e.g., certain PDFs consistently fail), update this file with a new "Known Issues" section.
3. When new actions are added to `docling-tools/actions/`, update the "Available Agent Actions" section.
4. If configuration changes (ports, paths, env vars), update accordingly.
5. Always verify the current state before making assertions about the system.

## File Map
```
~/Docling/                     ← This repository (documentation + skills)
├── AGENTS.md                  ← THIS FILE: Agent manual & self-cognition
├── .agent/                    
│   ├── SKILL.md               ← Skill definition for runtime context injection
│   └── update-context.sh      ← Script to regenerate context
├── docling-service/
│   ├── main.py                ← FastAPI app (Docling wrapper, port 8085)
│   ├── requirements.txt       ← Python dependencies
│   └── start.sh               ← Startup script
└── docling-tools/
    └── actions/
        └── docling_actions.py ← Sema4.ai @action definitions (port 8082)
```
