#!/usr/bin/env bash
# =============================================================================
# .agent/update-context.sh
# Ultra-advanced context snapshot for Docling Agent
# Version: 2.0.0
#
# USAGE:
#   ./update-context.sh              — full snapshot (default)
#   ./update-context.sh --full       — full snapshot + deep analysis
#   ./update-context.sh --quick      — fast snapshot (< 5 seconds)
#   ./update-context.sh --age        — print snapshot age and exit
#   ./update-context.sh --diff       — show what changed since last snapshot
#
# OUTPUT:
#   .agent/runtime-context.md        — primary context document
#   .agent/.context-meta.json        — machine-readable metadata
#   .agent/.last-snapshot-hash       — content hash for drift detection
# =============================================================================

set -euo pipefail

# ─── Configuration ────────────────────────────────────────────────────────────
AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$AGENT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$AGENT_DIR/..")"
CONTEXT_FILE="$AGENT_DIR/runtime-context.md"
META_FILE="$AGENT_DIR/.context-meta.json"
HASH_FILE="$AGENT_DIR/.last-snapshot-hash"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
SESSION_ID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null || date +%s%N | sha256sum | head -c 16)
MODE="${1:-}"

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[0;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log()  { echo -e "${CYAN}[CTX]${RESET} $*"; }
warn() { echo -e "${YELLOW}[WARN]${RESET} $*"; }
ok()   { echo -e "${GREEN}[OK]${RESET} $*"; }
err()  { echo -e "${RED}[ERR]${RESET} $*" >&2; }

# ─── Mode: --age ──────────────────────────────────────────────────────────────
if [[ "$MODE" == "--age" ]]; then
  if [[ -f "$META_FILE" ]]; then
    LAST_TS=$(python3 -c "import json,sys; d=json.load(open('$META_FILE')); print(d.get('timestamp','unknown'))" 2>/dev/null || echo "unknown")
    echo "Last snapshot: $LAST_TS"
    if [[ "$LAST_TS" != "unknown" ]]; then
      AGE_SECONDS=$(( $(date +%s) - $(date -d "$LAST_TS" +%s 2>/dev/null || echo 0) ))
      AGE_HOURS=$(( AGE_SECONDS / 3600 ))
      echo "Snapshot age: ${AGE_HOURS}h ${$(( (AGE_SECONDS % 3600) / 60 ))}m"
      [[ $AGE_HOURS -gt 24 ]] && warn "Context is STALE (> 24 hours). Run update-context.sh" && exit 1
      ok "Context is fresh."
    fi
  else
    err "No snapshot found. Run update-context.sh first."
    exit 1
  fi
  exit 0
fi

# ─── Mode: --diff ─────────────────────────────────────────────────────────────
if [[ "$MODE" == "--diff" ]]; then
  if [[ -f "$HASH_FILE" && -f "$CONTEXT_FILE" ]]; then
    OLD_HASH=$(cat "$HASH_FILE")
    NEW_HASH=$(sha256sum "$CONTEXT_FILE" | awk '{print $1}')
    if [[ "$OLD_HASH" == "$NEW_HASH" ]]; then
      ok "Context has not changed since last snapshot."
    else
      warn "Context drift detected!"
      echo "Old hash: $OLD_HASH"
      echo "New hash: $NEW_HASH"
    fi
  else
    err "No baseline for comparison. Run full snapshot first."
    exit 1
  fi
  exit 0
fi

# ─── Preflight ────────────────────────────────────────────────────────────────
log "Starting context snapshot [mode=${MODE:-full}] [session=$SESSION_ID]"
cd "$REPO_ROOT"

# ─── Collect: Git State ───────────────────────────────────────────────────────
GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "UNKNOWN")
GIT_HEAD=$(git rev-parse HEAD 2>/dev/null || echo "UNKNOWN")
GIT_HEAD_SHORT=$(git rev-parse --short HEAD 2>/dev/null || echo "UNKNOWN")
GIT_HEAD_MSG=$(git log -1 --format="%s" 2>/dev/null || echo "UNKNOWN")
GIT_HEAD_AUTHOR=$(git log -1 --format="%an <%ae>" 2>/dev/null || echo "UNKNOWN")
GIT_HEAD_DATE=$(git log -1 --format="%ai" 2>/dev/null || echo "UNKNOWN")
GIT_STATUS=$(git status --short 2>/dev/null || echo "")
GIT_STATUS_COUNT=$(echo "$GIT_STATUS" | grep -c "." 2>/dev/null || echo "0")
GIT_STASH_COUNT=$(git stash list 2>/dev/null | wc -l || echo "0")
GIT_REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "no remote")
GIT_AHEAD_BEHIND=$(git rev-list --left-right --count HEAD...@{upstream} 2>/dev/null || echo "0\t0")
GIT_AHEAD=$(echo "$GIT_AHEAD_BEHIND" | awk '{print $1}')
GIT_BEHIND=$(echo "$GIT_AHEAD_BEHIND" | awk '{print $2}')

# Recent commits
GIT_RECENT_COMMITS=$(git log --oneline -10 2>/dev/null || echo "unavailable")

# Changed files since last 24h
GIT_RECENT_FILES=$(git diff --name-only "HEAD~5" HEAD 2>/dev/null || echo "unavailable")

# Tags (for rollback points)
GIT_AGENT_TAGS=$(git tag --list "agent/*" | tail -5 2>/dev/null || echo "none")

# ─── Collect: Python Environment ──────────────────────────────────────────────
PYTHON_PATH=$(which python 2>/dev/null || which python3 2>/dev/null || echo "NOT FOUND")
PYTHON_VERSION=$("$PYTHON_PATH" --version 2>&1 || echo "UNKNOWN")
VENV_ACTIVE="${VIRTUAL_ENV:-none}"
VENV_PATH="${VIRTUAL_ENV:-$CONDA_PREFIX:-none}"

# Docling packages
DOCLING_VERSION=$(pip show docling 2>/dev/null | grep "^Version:" | awk '{print $2}' || echo "NOT INSTALLED")
DOCLING_CORE_VERSION=$(pip show docling-core 2>/dev/null | grep "^Version:" | awk '{print $2}' || echo "NOT INSTALLED")
DOCLING_PARSE_VERSION=$(pip show docling-parse 2>/dev/null | grep "^Version:" | awk '{print $2}' || echo "NOT INSTALLED")
DOCLING_IBM_VERSION=$(pip show docling-ibm-models 2>/dev/null | grep "^Version:" | awk '{print $2}' || echo "NOT INSTALLED")
DOCLING_LOCATION=$(pip show docling 2>/dev/null | grep "^Location:" | awk '{print $2}' || echo "N/A")

# Key deps
PYDANTIC_VERSION=$(pip show pydantic 2>/dev/null | grep "^Version:" | awk '{print $2}' || echo "NOT INSTALLED")
PYPDFIUM_VERSION=$(pip show pypdfium2 2>/dev/null | grep "^Version:" | awk '{print $2}' || echo "NOT INSTALLED")
EASYOCR_VERSION=$(pip show easyocr 2>/dev/null | grep "^Version:" | awk '{print $2}' || echo "NOT INSTALLED")
TESSERACT_VERSION=$(tesseract --version 2>&1 | head -1 || echo "NOT INSTALLED")

# ─── Collect: Project Structure ───────────────────────────────────────────────
PYPROJECT_VERSION=$(python3 -c "
import tomllib, pathlib
try:
    data = tomllib.loads(pathlib.Path('pyproject.toml').read_text())
    print(data.get('project',{}).get('version', data.get('tool',{}).get('poetry',{}).get('version','UNKNOWN')))
except: print('PARSE_ERROR')
" 2>/dev/null || grep -m1 '"version"' pyproject.toml 2>/dev/null | grep -oP '"\K[^"]+' || echo "UNKNOWN")

# File counts
PYTHON_FILE_COUNT=$(find docling/ -name "*.py" 2>/dev/null | wc -l || echo "0")
TEST_FILE_COUNT=$(find tests/ -name "test_*.py" 2>/dev/null | wc -l || echo "0")
DOC_FILE_COUNT=$(find docs/ -name "*.md" 2>/dev/null | wc -l || echo "0")

# Check for key architectural files
BACKENDS=$(ls docling/backend/*.py 2>/dev/null | xargs -I{} basename {} .py | tr '\n' ', ' || echo "UNKNOWN")
MODELS=$(ls docling/models/*.py 2>/dev/null | xargs -I{} basename {} .py | tr '\n' ', ' || echo "UNKNOWN")
PIPELINES=$(ls docling/pipeline/*.py 2>/dev/null | xargs -I{} basename {} .py | tr '\n' ', ' || echo "UNKNOWN")

# ─── Collect: Test Status (skip if --quick) ────────────────────────────────────
TEST_SUMMARY="[skipped in quick mode]"
if [[ "$MODE" != "--quick" ]]; then
  log "Running quick test probe..."
  TEST_SUMMARY=$(pytest tests/ --co -q 2>/dev/null | tail -3 || echo "pytest not available or tests failed to collect")
fi

# ─── Collect: Known Issues ────────────────────────────────────────────────────
KNOWN_ISSUES_FILE="$AGENT_DIR/known-issues.md"
OPEN_ISSUES="none"
if [[ -f "$KNOWN_ISSUES_FILE" ]]; then
  OPEN_ISSUES=$(grep -c "| \*\*Status\*\* | OPEN\|INVESTIGATING" "$KNOWN_ISSUES_FILE" 2>/dev/null || echo "0")
fi

# ─── Collect: Recent Changelog ────────────────────────────────────────────────
CHANGELOG_FILE="$AGENT_DIR/changelog-agent.md"
RECENT_CHANGES="none"
if [[ -f "$CHANGELOG_FILE" ]]; then
  RECENT_CHANGES=$(grep -A2 "^## \[" "$CHANGELOG_FILE" 2>/dev/null | head -20 || echo "empty")
fi

# ─── Collect: System Resources ────────────────────────────────────────────────
OS_INFO=$(uname -a 2>/dev/null | head -c 100 || echo "unknown")
DISK_USAGE=$(df -h . 2>/dev/null | tail -1 | awk '{print "Used: "$3" / "$2" ("$5")"}' || echo "unknown")
MEMORY=$(free -h 2>/dev/null | grep "^Mem:" | awk '{print "Used: "$3" / "$2}' || echo "unknown")

# ─── Collect: Action Detection ────────────────────────────────────────────────
# Detect what kind of work has been done recently
DETECTED_ACTIONS=""
if [[ -n "$GIT_STATUS" ]]; then
  if echo "$GIT_STATUS" | grep -q "\.py$"; then
    DETECTED_ACTIONS+="Python modifications detected. "
  fi
  if echo "$GIT_STATUS" | grep -q "test_"; then
    DETECTED_ACTIONS+="Test file changes detected. "
  fi
  if echo "$GIT_STATUS" | grep -q "pyproject\.toml\|requirements"; then
    DETECTED_ACTIONS+="⚠️ Dependency file changes detected — high risk. "
  fi
  if echo "$GIT_STATUS" | grep -q "CORE-PROTOCOL\|SKILL\.md"; then
    DETECTED_ACTIONS+="Agent protocol files modified. "
  fi
fi
[[ -z "$DETECTED_ACTIONS" ]] && DETECTED_ACTIONS="No uncommitted changes detected."

# ─── Detect: Documentation Drift Signals ─────────────────────────────────────
DOC_DRIFT_SIGNALS=""
if [[ "$MODE" == "--full" ]]; then
  log "Running documentation drift detection..."
  # Check if README imports work
  README_IMPORT=$(python3 -c "from docling.document_converter import DocumentConverter" 2>&1 && echo "OK" || echo "BROKEN")
  [[ "$README_IMPORT" != "OK" ]] && DOC_DRIFT_SIGNALS+="⚠️ Core import broken: $README_IMPORT. "

  # Check if CLI is accessible
  CLI_CHECK=$(python3 -m docling --help 2>/dev/null | head -1 || echo "CLI UNAVAILABLE")
  DOC_DRIFT_SIGNALS+="CLI: $CLI_CHECK. "
fi
[[ -z "$DOC_DRIFT_SIGNALS" ]] && DOC_DRIFT_SIGNALS="No drift signals detected [mode=$MODE]."

# ─── Write Context File ───────────────────────────────────────────────────────
log "Writing context to $CONTEXT_FILE..."

cat > "$CONTEXT_FILE" << CONTEXT_EOF
# Docling Agent — Runtime Context
<!-- AUTO-GENERATED by update-context.sh — DO NOT EDIT MANUALLY -->
<!-- Snapshot: $TIMESTAMP | Session: $SESSION_ID -->

> ⚠️ **This context expires in 24 hours.** Re-run \`.agent/update-context.sh\` if stale.
> Snapshot Mode: \`${MODE:-full}\`

---

## 1. Repository State

| Field | Value |
|-------|-------|
| **Branch** | \`$GIT_BRANCH\` |
| **HEAD Commit** | \`$GIT_HEAD_SHORT\` — $GIT_HEAD_MSG |
| **HEAD Full Hash** | \`$GIT_HEAD\` |
| **Author** | $GIT_HEAD_AUTHOR |
| **Commit Date** | $GIT_HEAD_DATE |
| **Remote** | $GIT_REMOTE_URL |
| **Ahead/Behind** | ↑$GIT_AHEAD ↓$GIT_BEHIND vs upstream |
| **Stashed Changes** | $GIT_STASH_COUNT |
| **Dirty Files** | $GIT_STATUS_COUNT |

### Uncommitted Changes
\`\`\`
${GIT_STATUS:-[clean — nothing to commit]}
\`\`\`

### Detected Action Context
$DETECTED_ACTIONS

### Recent Commits
\`\`\`
$GIT_RECENT_COMMITS
\`\`\`

### Recent Agent Rollback Tags
\`\`\`
${GIT_AGENT_TAGS:-none}
\`\`\`

---

## 2. Python Environment

| Package | Version |
|---------|---------|
| **Python** | $PYTHON_VERSION |
| **Venv Active** | $VENV_PATH |
| **docling** | $DOCLING_VERSION |
| **docling-core** | $DOCLING_CORE_VERSION |
| **docling-parse** | $DOCLING_PARSE_VERSION |
| **docling-ibm-models** | $DOCLING_IBM_VERSION |
| **pydantic** | $PYDANTIC_VERSION |
| **pypdfium2** | $PYPDFIUM_VERSION |
| **easyocr** | $EASYOCR_VERSION |
| **tesseract** | $TESSERACT_VERSION |

- Install location: \`$DOCLING_LOCATION\`

---

## 3. Project Structure

| Metric | Value |
|--------|-------|
| **pyproject.toml version** | $PYPROJECT_VERSION |
| **Python source files** | $PYTHON_FILE_COUNT |
| **Test files** | $TEST_FILE_COUNT |
| **Documentation pages** | $DOC_FILE_COUNT |

### Available Backends
\`\`\`
$BACKENDS
\`\`\`

### Available Models
\`\`\`
$MODELS
\`\`\`

### Available Pipelines
\`\`\`
$PIPELINES
\`\`\`

---

## 4. Test Status

\`\`\`
$TEST_SUMMARY
\`\`\`

---

## 5. Known Issues

- **Open issues:** $OPEN_ISSUES
- See \`.agent/known-issues.md\` for full list

---

## 6. Recent Agent Activity

\`\`\`
$RECENT_CHANGES
\`\`\`

---

## 7. Documentation Drift Signals

$DOC_DRIFT_SIGNALS

---

## 8. System Resources

| Resource | Status |
|----------|--------|
| **OS** | $OS_INFO |
| **Disk** | $DISK_USAGE |
| **Memory** | $MEMORY |

---

## 9. Snapshot Metadata

| Field | Value |
|-------|-------|
| **Generated** | $TIMESTAMP |
| **Session ID** | $SESSION_ID |
| **Generated by** | update-context.sh v2.0.0 |
| **Mode** | ${MODE:-full} |
| **Expires** | $(date -u -d "+24 hours" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -v+24H +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "24h from now") |

---
*Read this file completely before taking any action. No skimming.*
CONTEXT_EOF

# ─── Write Machine-Readable Metadata ─────────────────────────────────────────
cat > "$META_FILE" << META_EOF
{
  "timestamp": "$TIMESTAMP",
  "session_id": "$SESSION_ID",
  "mode": "${MODE:-full}",
  "git": {
    "branch": "$GIT_BRANCH",
    "head": "$GIT_HEAD",
    "head_short": "$GIT_HEAD_SHORT",
    "dirty_files": $GIT_STATUS_COUNT,
    "stash_count": $GIT_STASH_COUNT,
    "ahead": $GIT_AHEAD,
    "behind": $GIT_BEHIND
  },
  "python": {
    "version": "$PYTHON_VERSION",
    "docling": "$DOCLING_VERSION",
    "docling_core": "$DOCLING_CORE_VERSION"
  },
  "project": {
    "declared_version": "$PYPROJECT_VERSION",
    "python_files": $PYTHON_FILE_COUNT,
    "test_files": $TEST_FILE_COUNT
  },
  "issues": {
    "open": "$OPEN_ISSUES"
  },
  "schema_version": "2.0.0"
}
META_EOF

# ─── Compute and Store Content Hash ───────────────────────────────────────────
CONTENT_HASH=$(sha256sum "$CONTEXT_FILE" | awk '{print $1}')
echo "$CONTENT_HASH" > "$HASH_FILE"

# ─── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}  CONTEXT SNAPSHOT COMPLETE${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════════${RESET}"
echo -e "  Branch:      ${CYAN}$GIT_BRANCH${RESET} @ ${CYAN}$GIT_HEAD_SHORT${RESET}"
echo -e "  Docling:     ${CYAN}$DOCLING_VERSION${RESET}"
echo -e "  Dirty files: ${GIT_STATUS_COUNT:-0}"
echo -e "  Open issues: $OPEN_ISSUES"
echo -e "  Hash:        $CONTENT_HASH"
echo -e "  Output:      $CONTEXT_FILE"
echo -e "${BOLD}═══════════════════════════════════════════════════${RESET}"
echo ""

ok "Context snapshot complete. Session ID: $SESSION_ID"
