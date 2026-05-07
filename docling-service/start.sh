#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"

VENV=".venv"

if [ ! -d "$VENV" ]; then
  echo "Creating venv..."
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install --upgrade pip
  "$VENV/bin/pip" install -r requirements.txt
fi

echo "Starting docling-service on port 8085..."
"$VENV/bin/uvicorn" main:app --host 0.0.0.0 --port 8085 --workers 1
