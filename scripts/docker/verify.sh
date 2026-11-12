#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

echo "== Backend security scan =="
python backend/security_check.py

echo
echo "== Backend tests =="
python -m unittest discover -s backend/tests -v

echo
echo "== Flutter dependencies =="
flutter pub get

echo
echo "== Flutter tests =="
flutter test

echo
echo "== Flutter static analysis =="
flutter analyze --no-fatal-infos --no-fatal-warnings

echo
echo "All configured checks completed successfully."
