# docling-tools

Stack de procesamiento de documentos PDF/DOC con OCR, extracción de imágenes y conversión a Markdown.
Integrable con OpenAPI, MCP y agentes de IA vía Sema4.ai Action Server.

---

## Arquitectura

```
~/docling-service/          ← FastAPI + Docling (ML pesado, venv propio)
    port 8085               ← API REST + serving de imágenes estáticas

~/ai-research/docling-tools/ ← Sema4.ai Action Server (wrappers HTTP ligeros)
    port 8082               ← MCP endpoint + OpenAPI
```

Los agentes hablan con el Action Server (8082).
El Action Server delega el trabajo real al docling-service (8085).

---

## Requisitos del sistema

- Python 3.12 (`python3 --version`)
- `action-server` CLI instalado (`action-server --version`)
- Acceso a internet en primer arranque (descarga modelos EasyOCR ~50 MB)

---

## Instalación

### 1. docling-service

```bash
cd ~/docling-service

# Crear venv e instalar (solo la primera vez)
python3 -m venv .venv
.venv/bin/pip install --upgrade pip
.venv/bin/pip install -r requirements.txt
```

`requirements.txt` mínimo:
```
fastapi>=0.111.0,<1.0.0
uvicorn[standard]>=0.30.0,<1.0.0
docling==2.14.0
httpx>=0.27.0,<1.0.0
Pillow>=10.0.0,<11.0.0
python-multipart>=0.0.9
easyocr>=1.7.0,<2.0.0
```

### 2. Action Server (holotree)

El holotree se construye automáticamente al lanzar el Action Server por primera vez.
No instala nada de ML — solo `sema4ai-actions` y `httpx`.

`conda.yaml`:
```yaml
channels:
  - conda-forge
dependencies:
  - python=3.12
  - pip=24.*
  - pip:
      - sema4ai-actions>=1.0.0,<2.0.0
      - httpx>=0.27.0,<1.0.0
```

---

## Arranque

### Orden obligatorio: primero docling-service, luego Action Server.

```bash
# Terminal 1 — docling-service
cd ~/docling-service
./start.sh

# Terminal 2 — Action Server
cd ~/ai-research/docling-tools
action-server start --port 8082
```

Para exposición pública con bearer token:
```bash
action-server start --port 8082 --expose
```

---

## Variables de entorno

| Variable             | Defecto                  | Descripción                                      |
|----------------------|--------------------------|--------------------------------------------------|
| `DOCLING_SERVICE_URL`| `http://localhost:8085`  | URL del docling-service (usada por las actions)  |
| `DOCLING_IMAGES_DIR` | `/home/franjr/ai-research/public/images/docling` | Directorio donde se guardan las imágenes |

Ejemplo con override:
```bash
DOCLING_SERVICE_URL=http://192.168.1.100:8085 action-server start --port 8082
```

---

## Endpoints disponibles

### docling-service (puerto 8085)

| Método | Ruta              | Descripción                              |
|--------|-------------------|------------------------------------------|
| GET    | `/health`         | Estado del servicio + flag EasyOCR       |
| POST   | `/parse`          | Parse completo: texto + imágenes         |
| POST   | `/extract-images` | Solo extracción de imágenes              |
| POST   | `/to-markdown`    | Conversión a Markdown                    |
| GET    | `/openapi.json`   | Spec OpenAPI del servicio Docling        |
| GET    | `/public/images/docling/{filename}` | Imágenes extraídas  |

### Action Server (puerto 8082)

| Ruta            | Descripción                              |
|-----------------|------------------------------------------|
| `/mcp`          | Endpoint MCP para agentes                |
| `/openapi.json` | Spec OpenAPI de las actions              |
| `/`             | UI web del Action Server                 |

---

## Actions expuestas

### `parse_document`
Parse completo con OCR + extracción de imágenes.
```json
{
  "source": "/ruta/absoluta/al/archivo.pdf",
  "output_format": "markdown",
  "save_images": true,
  "public_base_url": ""
}
```

### `extract_and_save_images`
Solo imágenes, sin texto.
```json
{
  "source": "https://ejemplo.com/documento.pdf",
  "output_subdir": "docling",
  "public_base_url": ""
}
```

### `convert_to_markdown`
Conversión rápida a Markdown.
```json
{
  "source": "/ruta/al/archivo.pdf",
  "save_images": false,
  "public_base_url": ""
}
```

Todas devuelven JSON con `status`, `content`/`markdown`, `images[]`, `image_count`.

---

## Verificación rápida

```bash
# Health check
curl -s http://localhost:8085/health | python3 -m json.tool

# Smoke test con PDF local
curl -s -X POST http://localhost:8085/to-markdown \
  -H "Content-Type: application/json" \
  -d '{"source": "/ruta/a/archivo.pdf", "save_images": false}' \
  | python3 -m json.tool | head -20

# Verificar actions registradas
curl -s http://localhost:8082/openapi.json \
  | python3 -m json.tool | grep '"operationId"'

# Ver imágenes extraídas
ls /home/franjr/ai-research/public/images/docling/
```

---

## Estructura de carpetas

```
~/docling-service/
├── main.py                  ← FastAPI app (lógica Docling)
├── requirements.txt         ← deps Python (ML incluido)
├── start.sh                 ← script de arranque
└── .venv/                   ← entorno virtual (ignorar en git)

~/ai-research/docling-tools/
├── actions/
│   └── docling_actions.py   ← @action wrappers HTTP
├── conda.yaml               ← entorno holotree (sin ML)
├── package.yaml             ← config Action Server v2
└── README.md                ← este archivo

~/ai-research/public/
└── images/
    └── docling/             ← imágenes extraídas (servidas por docling-service)
```

---

## Integración con agentes

### MCP (Claude Desktop, Cursor, etc.)

Añadir a la config del cliente MCP:
```json
{
  "mcpServers": {
    "docling-tools": {
      "url": "http://localhost:8082/mcp"
    }
  }
}
```

### OpenAPI

El spec completo está en:
- Actions: `http://localhost:8082/openapi.json`
- Docling service directo: `http://localhost:8085/openapi.json`

---

## Notas

- Primera conversión es más lenta (~30 seg): EasyOCR descarga modelos al directorio `~/.EasyOCR/`.
  Las siguientes usan caché y son más rápidas (~20 seg para PDFs escaneados).
- OCR en CPU. Si tienes GPU NVIDIA, instala `torch` con CUDA en el venv de docling-service
  y elimina `use_gpu=False` de `main.py`.
- El docling-service procesa una request a la vez (`--workers 1`). Para concurrencia,
  usar `--workers 2` con cuidado (memoria RAM: ~2 GB por worker con modelos cargados).
