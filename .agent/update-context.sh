#!/bin/bash
# update-context.sh — Generates a live snapshot of the project state for agents.
# Usage: bash .agent/update-context.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SNAPSHOT="$SCRIPT_DIR/context-snapshot.json"

echo "📸 Generating context snapshot for agents..."

# Gather file contents into a structured JSON
# Using a temp file for safe JSON construction
TEMP_FILE=$(mktemp)

cat > "$TEMP_FILE" << JSONEOF
{
  "generated_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "project_root": "$PROJECT_DIR",

  "health_checks": {
    "docling_service": "$(curl -s --connect-timeout 2 http://localhost:8085/health 2>/dev/null || echo '{"status":"unreachable","note":"Service not running"}')",
    "action_server": "$(curl -s --connect-timeout 2 http://localhost:8082/openapi.json 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); print(json.dumps({"status":"ok","actions":list(d.get("paths",{}).keys())}))' 2>/dev/null || echo '{"status":"unreachable","note":"Action Server not running"}')"
  },

  "code_files": {
    "docling-service/main.py": "$(base64 -w 0 "$PROJECT_DIR/docling-service/main.py" 2>/dev/null || echo "NOT_FOUND")",
    "docling-service/requirements.txt": "$(cat "$PROJECT_DIR/docling-service/requirements.txt" 2>/dev/null || echo "NOT_FOUND")",
    "docling-service/start.sh": "$(cat "$PROJECT_DIR/docling-service/start.sh" 2>/dev/null || echo "NOT_FOUND")",
    "docling-tools/actions/docling_actions.py": "$(cat "$PROJECT_DIR/docling-tools/actions/docling_actions.py" 2>/dev/null || echo "NOT_FOUND")"
  },

  "git_status": "$(cd "$PROJECT_DIR" && git log --oneline -1 2>/dev/null || echo "no git history")",

  "note": "main.py content is base64-encoded to avoid JSON escaping issues. Use: echo '$base64_content' | base64 -d"
}
JSONEOF

mv "$TEMP_FILE" "$SNAPSHOT"
echo "✅ Snapshot saved to: $SNAPSHOT"
echo "   Generated at: $(date)"
