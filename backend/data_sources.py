"""Configurable school-data adapters used by Navigator's workbook API."""
from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

import requests
from fastapi import HTTPException

_ALLOWED_SHEETS = {"Classes", "BaseSchedule", "Supplements", "Rooms", "Places", "Announcements"}


def load_configured_sheet(sheet_name: str) -> list[dict[str, Any]] | None:
    """Return data for JSON/HTTP adapters, or None to use the legacy Yandex workbook path."""
    if sheet_name not in _ALLOWED_SHEETS:
        raise HTTPException(status_code=404, detail="Sheet not found")
    source = os.getenv("NAVIGATOR_DATA_SOURCE", "yandex").strip().lower()
    if source == "yandex":
        return None
    if source == "json":
        path = os.getenv("NAVIGATOR_DATA_JSON_PATH", "").strip()
        if not path:
            raise HTTPException(status_code=503, detail="NAVIGATOR_DATA_JSON_PATH is not configured")
        try:
            payload = json.loads(Path(path).read_text(encoding="utf-8"))
            rows = payload.get(sheet_name, [])
            if not isinstance(rows, list) or any(not isinstance(item, dict) for item in rows):
                raise ValueError("Expected a list of objects")
            return rows
        except (OSError, ValueError, TypeError):
            raise HTTPException(status_code=502, detail="Configured JSON data source is invalid or unavailable")
    if source == "http":
        base_url = os.getenv("NAVIGATOR_DATA_API_URL", "").strip().rstrip("/")
        token = os.getenv("NAVIGATOR_DATA_API_TOKEN", "").strip()
        if not base_url.startswith("https://") and not base_url.startswith("http://localhost"):
            raise HTTPException(status_code=503, detail="Data API URL must use HTTPS")
        if not base_url:
            raise HTTPException(status_code=503, detail="NAVIGATOR_DATA_API_URL is not configured")
        try:
            response = requests.get(f"{base_url}/{sheet_name}", headers={"Authorization": f"Bearer {token}"} if token else {}, timeout=10)
            response.raise_for_status()
            payload = response.json()
            rows = payload.get("data", payload) if isinstance(payload, dict) else payload
            if not isinstance(rows, list) or any(not isinstance(item, dict) for item in rows):
                raise ValueError("Expected a list of objects")
            return rows
        except (requests.RequestException, ValueError):
            raise HTTPException(status_code=502, detail="Configured data API is unavailable or returned invalid data")
    raise HTTPException(status_code=503, detail="Unsupported NAVIGATOR_DATA_SOURCE; use yandex, json, or http")
