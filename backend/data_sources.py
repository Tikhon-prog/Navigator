"""Configurable JSON and HTTPS adapters for school data."""
from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit

import requests
from fastapi import HTTPException

_ALLOWED_SHEETS = {
    "Classes", "BaseSchedule", "Supplements", "Rooms", "Places", "Announcements",
}


def _validate_rows(rows: Any) -> list[dict[str, Any]]:
    if not isinstance(rows, list) or any(not isinstance(item, dict) for item in rows):
        raise ValueError("Expected a list of objects")
    return rows


def load_configured_sheet(sheet_name: str) -> list[dict[str, Any]]:
    """Load one allowlisted collection from a local JSON file or configured HTTPS API."""
    if sheet_name not in _ALLOWED_SHEETS:
        raise HTTPException(status_code=404, detail="Data collection not found")

    source = os.getenv("NAVIGATOR_DATA_SOURCE", "json").strip().lower()
    if source == "json":
        path_text = os.getenv("NAVIGATOR_DATA_JSON_PATH", "").strip()
        if not path_text:
            raise HTTPException(status_code=503, detail="NAVIGATOR_DATA_JSON_PATH is not configured")
        try:
            payload = json.loads(Path(path_text).read_text(encoding="utf-8"))
            if not isinstance(payload, dict):
                raise ValueError("Expected a JSON object keyed by collection name")
            return _validate_rows(payload.get(sheet_name, []))
        except (OSError, UnicodeError, json.JSONDecodeError, ValueError, TypeError):
            raise HTTPException(status_code=502, detail="Configured JSON data source is invalid or unavailable")

    if source == "http":
        base_url = os.getenv("NAVIGATOR_DATA_API_URL", "").strip().rstrip("/")
        token = os.getenv("NAVIGATOR_DATA_API_TOKEN", "").strip()
        try:
            parsed = urlsplit(base_url)
        except ValueError:
            raise HTTPException(status_code=503, detail="NAVIGATOR_DATA_API_URL is invalid")
        is_local_http = parsed.scheme == "http" and parsed.hostname in {"localhost", "127.0.0.1", "::1"}
        if parsed.scheme != "https" and not is_local_http:
            raise HTTPException(status_code=503, detail="Data API URL must use HTTPS")
        if not parsed.hostname:
            raise HTTPException(status_code=503, detail="NAVIGATOR_DATA_API_URL is not configured")
        if parsed.username or parsed.password or parsed.query or parsed.fragment:
            raise HTTPException(
                status_code=503,
                detail="Data API URL must not contain credentials, query parameters or fragments",
            )
        try:
            response = requests.get(
                f"{base_url}/{sheet_name}",
                headers={
                    "Accept": "application/json",
                    **({"Authorization": f"Bearer {token}"} if token else {}),
                },
                timeout=10,
                allow_redirects=False,
            )
            if 300 <= response.status_code < 400:
                raise ValueError("Redirects are not allowed for configured data APIs")
            response.raise_for_status()
            payload = response.json()
            rows = payload.get("data") if isinstance(payload, dict) else payload
            return _validate_rows(rows)
        except (requests.RequestException, ValueError, TypeError):
            raise HTTPException(status_code=502, detail="Configured data API is unavailable or returned invalid data")

    raise HTTPException(
        status_code=503,
        detail="Unsupported NAVIGATOR_DATA_SOURCE; choose json or http",
    )
