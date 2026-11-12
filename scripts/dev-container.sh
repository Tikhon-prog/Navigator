#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker Engine is not installed or is not on PATH." >&2
  exit 1
fi
if ! docker compose version >/dev/null 2>&1; then
  echo "Docker Compose plugin is unavailable. Install the Compose plugin for Docker Engine." >&2
  exit 1
fi

exec docker compose -f compose.dev.yaml run --build --rm flutter-dev
