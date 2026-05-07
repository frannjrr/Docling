#!/usr/bin/env bash
# =============================================================================
# .agent/health-check.sh
# Deep health diagnostics for Docling Agent
# Version: 2.0.0
#
# USAGE:
#   ./health-check.sh               — standard check
#   ./health-check.sh --quick       — fast check (< 10 seconds)
#   ./health-check.sh --full        — deep check (runs actual pipeline)
#   ./health-check.sh --pipeline    — pipeline-only E2E test
#   ./health-check.sh --report      — output full JSON report
#
# EXIT CODES:
#   0 — All checks passed. Proceed normally.
#   1 — Non-critical issues detected. Proceed with caution.
#   2 — Critical failure. DO NOT proceed. Escalate to human.
# =============================================================================

set -euo pipefail

AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$AGENT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$AGENT_DIR/..")"
MODE="${1:-}"
REPORT_FILE="$AGENT_DIR/.health-report.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[0;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

# ─── State tracking ───────────────────────────────────────────────────────────
CHECKS_PASSED=0
CHECKS_WARNED=0
CHECKS_FAILED=0
CRITICAL_FAILURES=()
WARNINGS=()
MAX_EXIT=0

pass()  { echo -e "  ${GREEN}✓${RESET} $*"; ((CHECKS_PASSED++)); }
warn()  { echo -e "  ${YELLOW}⚠${RESET} $*"; ((CHECKS_WARNED++)); WARNINGS+=("$*"); [[ $MAX_EXIT -lt 1 ]] && MAX_EXIT=1; }
fail()  { echo -e "  ${RED}✗${RESET} $*"; ((CHECKS_FAILED++)); CRITICAL_FAILURES+=("$*"); MAX_EXIT=2; }
info()  { echo -e "  ${CYAN}→${RESET} $*"; }
header(){ echo -e "\n${BOLD}── $* ──────────────────────────────────────────${RESET}"; }

cd "$REPO_ROOT"

echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}  DOCLING AGENT HEALTH CHECK  [$(date -u '+%H:%M:%S UTC')]${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════════${RESET}"
echo -e "  Mode: ${MODE:-standard}"

# ═══════════════════════════════════════════════════
# CHECK GROUP 1: GIT INTEGRITY
# ═══════════════════════════════════════════════════
header "1. Git Integrity"

if git rev-parse --git-dir > /dev/null 2>&1; then
  pass "Git repository detected"
  BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  HEAD=$(git rev-parse --short HEAD 2>/dev/null)
  info "Branch: $BRANCH @ $HEAD"

  # Check for merge conflicts
  if git diff --check 2>/dev/null | grep -q "conflict"; then
    fail "Merge conflict markers detected in working tree"
  else
    pass "No merge conflict markers"
  fi

  # Check index
  if git fsck --no-progress --quiet 2>&1 | grep -q "error\|corrupt"; then
    fail "Git object corruption detected — run: git fsck"
  else
    pass "Git object store integrity OK"
  fi

  # Check for large uncommitted secrets-like patterns
  DIRTY_COUNT=$(git status --porcelain | wc -l)
  if [[ $DIRTY_COUNT -gt 20 ]]; then
    warn "High number of uncommitted changes ($DIRTY_COUNT files) — review before proceeding"
  elif [[ $DIRTY_COUNT -gt 0 ]]; then
    info "Uncommitted changes: $DIRTY_COUNT files"
  else
    pass "Working tree is clean"
  fi

  # Check for agent rollback tags
  ROLLBACK_TAGS=$(git tag --list "agent/*" | wc -l)
  info "Agent rollback checkpoints available: $ROLLBACK_TAGS"
else
  fail "Not a git repository — agent requires git"
fi

# ═══════════════════════════════════════════════════
# CHECK GROUP 2: PYTHON ENVIRONMENT
# ═══════════════════════════════════════════════════
header "2. Python Environment"

PYTHON_BIN=$(which python 2>/dev/null || which python3 2>/dev/null || echo "")
if [[ -z "$PYTHON_BIN" ]]; then
  fail "Python not found in PATH"
else
  PYTHON_VERSION_RAW=$("$PYTHON_BIN" --version 2>&1)
  PYTHON_MAJOR=$("$PYTHON_BIN" -c "import sys; print(sys.version_info.major)")
  PYTHON_MINOR=$("$PYTHON_BIN" -c "import sys; print(sys.version_info.minor)")

  if [[ "$PYTHON_MAJOR" -ge 3 && "$PYTHON_MINOR" -ge 10 ]]; then
    pass "Python version: $PYTHON_VERSION_RAW (≥ 3.10 required)"
  elif [[ "$PYTHON_MAJOR" -ge 3 && "$PYTHON_MINOR" -ge 9 ]]; then
    warn "Python $PYTHON_VERSION_RAW — Docling >= 2.70.0 requires Python 3.10+"
  else
    fail "Python $PYTHON_VERSION_RAW — INCOMPATIBLE. Minimum: Python 3.10"
  fi

  # Virtual environment check
  if [[ -n "${VIRTUAL_ENV:-}" ]]; then
    pass "Virtual environment active: $VIRTUAL_ENV"
  elif [[ -n "${CONDA_PREFIX:-}" ]]; then
    pass "Conda environment active: $CONDA_PREFIX"
  else
    warn "No virtual environment detected — running in system Python (risk of dependency conflicts)"
  fi
fi

# ═══════════════════════════════════════════════════
# CHECK GROUP 3: DOCLING PACKAGE INTEGRITY
# ═══════════════════════════════════════════════════
header "3. Docling Package Integrity"

check_package() {
  local pkg="$1"
  local required="${2:-false}"
  local version
  version=$(pip show "$pkg" 2>/dev/null | grep "^Version:" | awk '{print $2}')
  if [[ -n "$version" ]]; then
    pass "$pkg: $version"
    echo "$version"
  else
    if [[ "$required" == "true" ]]; then
      fail "$pkg: NOT INSTALLED (required)"
    else
      warn "$pkg: NOT INSTALLED (optional)"
    fi
    echo "NOT_INSTALLED"
  fi
}

DOCLING_VER=$(check_package "docling" "true")
check_package "docling-core" "true" > /dev/null
check_package "docling-parse" "false" > /dev/null
check_package "docling-ibm-models" "false" > /dev/null

# Version consistency check
PYPROJECT_VER=$(python3 -c "
import tomllib, pathlib
try:
    data = tomllib.loads(pathlib.Path('pyproject.toml').read_text())
    v = data.get('project',{}).get('version') or data.get('tool',{}).get('poetry',{}).get('version','')
    print(v or 'UNKNOWN')
except Exception as e:
    print('PARSE_ERROR')
" 2>/dev/null || echo "UNKNOWN")

if [[ "$DOCLING_VER" != "NOT_INSTALLED" && "$PYPROJECT_VER" != "UNKNOWN" ]]; then
  if [[ "$DOCLING_VER" == "$PYPROJECT_VER" ]]; then
    pass "Installed version matches pyproject.toml ($PYPROJECT_VER)"
  else
    warn "Version mismatch: installed=$DOCLING_VER, pyproject.toml=$PYPROJECT_VER"
  fi
fi

# Core import test
if "$PYTHON_BIN" -c "from docling.document_converter import DocumentConverter" 2>/dev/null; then
  pass "Core import: DocumentConverter importable"
else
  fail "Core import FAILED: 'from docling.document_converter import DocumentConverter'"
fi

# ═══════════════════════════════════════════════════
# CHECK GROUP 4: DEPENDENCY HEALTH
# ═══════════════════════════════════════════════════
if [[ "$MODE" != "--quick" ]]; then
  header "4. Critical Dependencies"

  # pypdfium2
  if "$PYTHON_BIN" -c "import pypdfium2" 2>/dev/null; then
    pass "pypdfium2: importable"
  else
    warn "pypdfium2: not importable (PDF processing may be limited)"
  fi

  # pydantic
  PYDANTIC_VER=$(pip show pydantic 2>/dev/null | grep "^Version:" | awk '{print $2}')
  if [[ -n "$PYDANTIC_VER" ]]; then
    PYDANTIC_MAJOR=$(echo "$PYDANTIC_VER" | cut -d. -f1)
    if [[ "$PYDANTIC_MAJOR" -ge 2 ]]; then
      pass "pydantic: $PYDANTIC_VER (v2 — compatible)"
    else
      warn "pydantic: $PYDANTIC_VER (v1 — may cause compatibility issues)"
    fi
  else
    fail "pydantic: NOT INSTALLED"
  fi

  # PIL / Pillow
  if "$PYTHON_BIN" -c "import PIL; print(PIL.__version__)" 2>/dev/null; then
    pass "Pillow: importable"
  else
    warn "Pillow: not importable (image processing may be limited)"
  fi

  # Optional: tesseract
  if tesseract --version > /dev/null 2>&1; then
    TESS_VER=$(tesseract --version 2>&1 | head -1)
    pass "Tesseract OCR: $TESS_VER"
  else
    info "Tesseract: not installed (optional — EasyOCR can be used instead)"
  fi
fi

# ═══════════════════════════════════════════════════
# CHECK GROUP 5: PROJECT STRUCTURE INTEGRITY
# ═══════════════════════════════════════════════════
header "5. Project Structure Integrity"

check_path() {
  local path="$1"
  local label="${2:-$path}"
  if [[ -e "$path" ]]; then
    pass "$label: present"
  else
    fail "$label: MISSING ($path)"
  fi
}

check_path "pyproject.toml" "pyproject.toml"
check_path "docling/" "docling/ package"
check_path "docling/document_converter.py" "DocumentConverter"
check_path "docling/datamodel/base_models.py" "InputFormat definitions"
check_path "docling/datamodel/pipeline_options.py" "Pipeline options"
check_path "docling/pipeline/" "Pipeline directory"
check_path "docling/backend/" "Backend directory"
check_path "docling/models/" "Models directory"
check_path "tests/" "Test suite"

# Check for __init__.py in key packages
for pkg in docling docling/datamodel docling/pipeline docling/backend docling/models; do
  if [[ -f "$pkg/__init__.py" ]]; then
    pass "$pkg/__init__.py present"
  else
    warn "$pkg/__init__.py MISSING (may affect imports)"
  fi
done

# ═══════════════════════════════════════════════════
# CHECK GROUP 6: AGENT FILES INTEGRITY
# ═══════════════════════════════════════════════════
header "6. Agent System Integrity"

AGENT_FILES=(
  ".agent/SKILL.md"
  ".agent/CORE-PROTOCOL.md"
  ".agent/update-context.sh"
  ".agent/health-check.sh"
  ".agent/improve.sh"
  ".agent/self-audit.sh"
  ".agent/changelog-agent.md"
)

for f in "${AGENT_FILES[@]}"; do
  if [[ -f "$f" ]]; then
    pass "$f: present"
  else
    warn "$f: MISSING — agent system degraded"
  fi
done

# Check context freshness
if [[ -f ".agent/.context-meta.json" ]]; then
  SNAP_TS=$(python3 -c "import json; d=json.load(open('.agent/.context-meta.json')); print(d.get('timestamp',''))" 2>/dev/null || echo "")
  if [[ -n "$SNAP_TS" ]]; then
    AGE_SECONDS=$(( $(date +%s) - $(date -d "$SNAP_TS" +%s 2>/dev/null || echo 0) ))
    AGE_HOURS=$(( AGE_SECONDS / 3600 ))
    if [[ $AGE_HOURS -gt 24 ]]; then
      warn "Context snapshot is STALE ($AGE_HOURS hours old) — run update-context.sh"
    else
      pass "Context snapshot is fresh ($AGE_HOURS hours old)"
    fi
  fi
else
  warn "No context snapshot found — run update-context.sh before working"
fi

# ═══════════════════════════════════════════════════
# CHECK GROUP 7: TEST SUITE HEALTH
# ═══════════════════════════════════════════════════
if [[ "$MODE" != "--quick" ]]; then
  header "7. Test Suite Health"

  if command -v pytest &> /dev/null; then
    pass "pytest: available"
    # Only collect, don't run (fast)
    COLLECT_OUTPUT=$(pytest tests/ --collect-only -q 2>&1 | tail -3 || echo "collection failed")
    info "Test collection: $COLLECT_OUTPUT"
  else
    warn "pytest: not found — cannot validate tests"
  fi

  # Check for mypy
  if command -v mypy &> /dev/null; then
    pass "mypy: available"
  else
    info "mypy: not installed (type checking unavailable)"
  fi

  # Check for ruff/flake8
  if command -v ruff &> /dev/null; then
    pass "ruff: available (linting)"
  elif command -v flake8 &> /dev/null; then
    pass "flake8: available (linting)"
  else
    info "ruff/flake8: not installed (linting unavailable)"
  fi
fi

# ═══════════════════════════════════════════════════
# CHECK GROUP 8: E2E PIPELINE TEST (--full or --pipeline only)
# ═══════════════════════════════════════════════════
if [[ "$MODE" == "--full" || "$MODE" == "--pipeline" ]]; then
  header "8. End-to-End Pipeline Test"

  E2E_RESULT=$("$PYTHON_BIN" -c "
from docling.document_converter import DocumentConverter
import tempfile, os

# Create a minimal test PDF or text doc
test_content = 'Hello from Docling health check.'
with tempfile.NamedTemporaryFile(suffix='.txt', mode='w', delete=False) as f:
    f.write(test_content)
    tmp_path = f.name

try:
    converter = DocumentConverter()
    result = converter.convert(tmp_path)
    doc = result.document
    text_items = len(doc.texts)
    md = doc.export_to_markdown()
    assert len(md) > 0, 'Empty markdown output'
    print(f'OK: {text_items} text items, {len(md)} chars markdown')
except Exception as e:
    print(f'FAIL: {e}')
finally:
    os.unlink(tmp_path)
" 2>&1 || echo "FAIL: exception during E2E test")

  if echo "$E2E_RESULT" | grep -q "^OK:"; then
    pass "E2E pipeline: $E2E_RESULT"
  else
    fail "E2E pipeline FAILED: $E2E_RESULT"
  fi
fi

# ═══════════════════════════════════════════════════
# SUMMARY REPORT
# ═══════════════════════════════════════════════════
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}  HEALTH CHECK SUMMARY${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════════${RESET}"
echo -e "  ${GREEN}Passed:${RESET}   $CHECKS_PASSED"
echo -e "  ${YELLOW}Warnings:${RESET} $CHECKS_WARNED"
echo -e "  ${RED}Failed:${RESET}   $CHECKS_FAILED"
echo ""

if [[ $CHECKS_FAILED -gt 0 ]]; then
  echo -e "${RED}${BOLD}  CRITICAL FAILURES:${RESET}"
  for f in "${CRITICAL_FAILURES[@]}"; do
    echo -e "  ${RED}✗${RESET} $f"
  done
  echo ""
fi

if [[ $CHECKS_WARNED -gt 0 && $CHECKS_FAILED -eq 0 ]]; then
  echo -e "${YELLOW}${BOLD}  WARNINGS (non-blocking):${RESET}"
  for w in "${WARNINGS[@]}"; do
    echo -e "  ${YELLOW}⚠${RESET} $w"
  done
  echo ""
fi

case $MAX_EXIT in
  0) echo -e "${GREEN}${BOLD}  ✓ ALL CHECKS PASSED — Safe to proceed${RESET}" ;;
  1) echo -e "${YELLOW}${BOLD}  ⚠ DEGRADED STATE — Proceed with caution${RESET}" ;;
  2) echo -e "${RED}${BOLD}  ✗ CRITICAL FAILURE — DO NOT PROCEED — Escalate to human${RESET}" ;;
esac

echo -e "${BOLD}═══════════════════════════════════════════════════${RESET}"
echo ""

# Write JSON report
cat > "$REPORT_FILE" << REPORT_EOF
{
  "timestamp": "$TIMESTAMP",
  "mode": "${MODE:-standard}",
  "result": $([ $MAX_EXIT -eq 0 ] && echo '"PASS"' || [ $MAX_EXIT -eq 1 ] && echo '"WARN"' || echo '"FAIL"'),
  "exit_code": $MAX_EXIT,
  "checks": {
    "passed": $CHECKS_PASSED,
    "warned": $CHECKS_WARNED,
    "failed": $CHECKS_FAILED
  },
  "critical_failures": [$(printf '"%s",' "${CRITICAL_FAILURES[@]}" 2>/dev/null | sed 's/,$//')]
}
REPORT_EOF

exit $MAX_EXIT
