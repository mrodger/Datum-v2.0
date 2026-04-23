#!/usr/bin/env bash
# build.sh — Build or rebuild the standalone Codex UI container.
set -euo pipefail
UI_DIR="$(dirname "$0")/../ui"

if [ ! -d "$UI_DIR" ]; then
    echo "Standalone UI not provisioned. Run bootstrap.sh first."
    exit 1
fi

cd "$UI_DIR"
echo "Building codex-ui container..."
docker compose build
echo "Done. Start with: docker compose up -d"
