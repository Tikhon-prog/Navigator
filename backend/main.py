"""HTTP API for the «Поколение» school app."""
from __future__ import annotations

import os
from pathlib import Path
from typing import Any

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware

BASE_DIR = Path(__file__).resolve().parent
load_dotenv(BASE_DIR.parent / ".env")
load_dotenv(BASE_DIR / ".env")

from .data_sources import load_configured_sheet
from .school_api import normalize_class_id, router as school_services_router
from .sso_api import router as school_sso_router
from .notification_api import router as notification_router
from .rbac_api import router as school_rbac_router
from .polls_api import router as polls_router

PUBLIC_READ_SHEETS = frozenset({
    "Classes", "BaseSchedule", "Rooms", "Places", "Announcements",
})
INTERNAL_READ_SHEETS = PUBLIC_READ_SHEETS | {"Supplements"}

app = FastAPI(
    title="Поколение — сервер школы",
    description="API школьного приложения",
    version="0.2.1",
)
app.include_router(school_services_router)
app.include_router(school_sso_router)
app.include_router(notification_router)
app.include_router(school_rbac_router)
app.include_router(polls_router)

_cors_origins = [
    origin.strip()
    for origin in os.getenv("NAVIGATOR_ALLOWED_ORIGINS", "").split(",")
    if origin.strip()
]
app.add_middleware(
    CORSMiddleware,
    # Native Android/iOS/desktop clients do not use browser CORS. For web/PWA,
    # require an explicit school portal origin instead of allowing every website.
    allow_origins=_cors_origins,
    allow_credentials=False,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"],
    allow_headers=["Accept", "Authorization", "Content-Type"],
)


def _lesson_number_sort_value(item: dict[str, Any]) -> int:
    """Return a stable integer ordering even when a source sends text labels."""
    raw = item.get("lesson_number")
    try:
        return int(raw or 0)
    except (TypeError, ValueError):
        import re

        match = re.search(r"\d+", str(raw or ""))
        return int(match.group(0)) if match else 0


def read_sheet(sheet_name: str) -> list[dict[str, Any]]:
    """Read an approved school-data collection from the configured source."""
    if sheet_name not in INTERNAL_READ_SHEETS:
        raise HTTPException(status_code=404, detail="Data collection not found")
    rows = load_configured_sheet(sheet_name)
    if not isinstance(rows, list) or any(not isinstance(row, dict) for row in rows):
        raise HTTPException(status_code=502, detail="School data source returned an invalid collection")
    return rows


@app.get("/")
def root() -> dict[str, str]:
    return {
        "name": "Поколение — сервер школы",
        "version": "0.2.1",
        "status": "ok",
    }


@app.get("/api/health")
def health() -> dict[str, Any]:
    source = os.getenv("NAVIGATOR_DATA_SOURCE", "json").strip().lower()
    try:
        sample = load_configured_sheet("Classes")
        return {"status": "ok", "source": source, "sample_rows": len(sample)}
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(status_code=502, detail="School data source is temporarily unavailable")


@app.get("/api/sheets")
def get_sheets() -> dict[str, list[str]]:
    return {"sheets": sorted(PUBLIC_READ_SHEETS)}


@app.get("/api/schema/{sheet_name}")
def get_schema(sheet_name: str) -> dict[str, Any]:
    if sheet_name not in PUBLIC_READ_SHEETS:
        raise HTTPException(status_code=404, detail="Data collection not found")
    rows = read_sheet(sheet_name)
    return {"sheet": sheet_name, "columns": list(rows[0].keys()) if rows else []}


@app.get("/api/classes")
def get_classes() -> dict[str, Any]:
    return {"data": read_sheet("Classes")}


@app.get("/api/classes/{class_id}")
def get_class(class_id: str) -> dict[str, Any]:
    for item in read_sheet("Classes"):
        if str(item.get("id")) == class_id:
            return item
    raise HTTPException(status_code=404, detail="Class not found")


@app.get("/api/schedule")
def get_schedule(
    class_id: str | None = Query(None),
    weekday: int | None = Query(None, ge=1, le=7),
) -> dict[str, Any]:
    schedule = read_sheet("BaseSchedule")
    if class_id is not None:
        schedule = [item for item in schedule if str(item.get("class_id")) == class_id]
    if weekday is not None:
        schedule = [item for item in schedule if str(item.get("weekday")) == str(weekday)]
    schedule.sort(key=lambda item: (
        str(item.get("weekday") or ""),
        _lesson_number_sort_value(item),
    ))
    return {"data": schedule}


@app.get("/api/schedule/{class_id}/{weekday}")
def get_class_schedule(class_id: str, weekday: int) -> dict[str, Any]:
    if weekday < 1 or weekday > 7:
        raise HTTPException(status_code=400, detail="weekday must be between 1 and 7")
    result = [
        item for item in read_sheet("BaseSchedule")
        if str(item.get("class_id")) == class_id
        and str(item.get("weekday")) == str(weekday)
    ]
    result.sort(key=_lesson_number_sort_value)
    return {"class_id": class_id, "weekday": weekday, "data": result}


@app.get("/api/supplements")
def get_supplements() -> None:
    # Student-linked activity records are private and available only through
    # authenticated, role-scoped endpoints under /api/v2.
    raise HTTPException(
        status_code=403,
        detail="Student activity records are private; use authenticated /api/v2 endpoints",
    )


@app.get("/api/rooms")
def get_rooms(floor: int | None = None, search: str | None = None) -> dict[str, Any]:
    rooms = read_sheet("Rooms")
    if floor is not None:
        rooms = [item for item in rooms if str(item.get("floor")) == str(floor)]
    if search:
        query = search.casefold()
        rooms = [
            item for item in rooms
            if query in str(item.get("name") or "").casefold()
            or query in str(item.get("description") or "").casefold()
        ]
    return {"data": rooms}


@app.get("/api/places")
def get_places(floor: int | None = None, search: str | None = None) -> dict[str, Any]:
    places = read_sheet("Places")
    if floor is not None:
        places = [item for item in places if str(item.get("floor")) == str(floor)]
    if search:
        query = search.casefold()
        places = [
            item for item in places
            if query in str(item.get("name") or "").casefold()
            or query in str(item.get("description") or "").casefold()
        ]
    return {"data": places}


def _normalize_class_key(value: Any) -> str:
    return normalize_class_id(value)


def _visible_announcements(
    class_id: str | None = None,
    *,
    include_class_targeted: bool = False,
) -> list[dict[str, Any]]:
    data = read_sheet("Announcements")
    target_key = _normalize_class_key(class_id)
    # Anonymous callers cannot choose a class ID to view private announcements.
    if not include_class_targeted or not target_key:
        data = [item for item in data if not _normalize_class_key(item.get("target_class_id"))]
    else:
        data = [
            item for item in data
            if not _normalize_class_key(item.get("target_class_id"))
            or _normalize_class_key(item.get("target_class_id")) == target_key
        ]
    data.sort(key=lambda item: str(item.get("published_at") or ""), reverse=True)
    return data


@app.get("/api/announcements")
def get_announcements(class_id: str | None = None) -> dict[str, Any]:
    return {"data": _visible_announcements(class_id)}


@app.get("/api/settings")
def get_settings() -> None:
    raise HTTPException(status_code=404, detail="Not found")


@app.get("/api/devices")
def get_devices() -> None:
    raise HTTPException(status_code=404, detail="Not found")


@app.get("/api/data/{sheet_name}")
def get_sheet_data(sheet_name: str, class_id: str | None = None) -> dict[str, Any]:
    if sheet_name not in PUBLIC_READ_SHEETS:
        raise HTTPException(status_code=404, detail="Data collection not found")
    data = _visible_announcements(class_id) if sheet_name == "Announcements" else read_sheet(sheet_name)
    return {"sheet": sheet_name, "data": data}
