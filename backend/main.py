from pathlib import Path
from datetime import datetime, time
from typing import Any
from time import monotonic

import io
import os
import requests
import openpyxl

from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from dotenv import load_dotenv

# Load secrets before importing modules that read environment variables at import time.
load_dotenv(Path(__file__).resolve().parent.parent / ".env")

from .school_api import router as school_services_router
from .sso_api import router as school_sso_router
from .notification_api import router as notification_router
from .data_sources import load_configured_sheet






# ============================================================
# CONFIG
# ============================================================

BASE_DIR = Path(__file__).resolve().parent
load_dotenv(BASE_DIR / ".env")

YANDEX_API = "https://cloud-api.yandex.net/v1/disk"

YANDEX_OAUTH_TOKEN = os.getenv("YANDEX_OAUTH_TOKEN")
YANDEX_FILE_PATH = os.getenv(
    "YANDEX_FILE_PATH",
    "app:/Navigator_Master.xlsx",
)

# Cache the workbook briefly so unauthenticated read traffic cannot trigger a
# Yandex Disk download for every single API request.
_WORKBOOK_CACHE_TTL_SECONDS = 30
_cached_workbook_bytes: bytes | None = None
_cached_workbook_at = 0.0


# ============================================================
# APP
# ============================================================

# Only these sheets are intended for unauthenticated, read-only school app access.
# Never expose Admins, Devices, AuditLog, or Settings through generic endpoints.
PUBLIC_READ_SHEETS = frozenset({
    "Classes",
    "BaseSchedule",
    "Supplements",
    "Rooms",
    "Places",
    "Announcements",
})

app = FastAPI(
    title="Поколение — сервер школы",
    description="Backend школьного навигатора",
    version="1.0.0",
)

# Separate authenticated API for accounts, scoped student access, and announcements.
app.include_router(school_services_router)
app.include_router(school_sso_router)
app.include_router(notification_router)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    # This backend currently exposes read-only endpoints only.
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"],
    allow_headers=["Accept", "Authorization", "Content-Type"],
)


# ============================================================
# YANDEX DISK
# ============================================================

def get_token():
    token = os.getenv("YANDEX_OAUTH_TOKEN")

    if not token:
        raise HTTPException(
            status_code=500,
            detail="YANDEX_OAUTH_TOKEN is not configured",
        )

    return token


def yandex_headers():
    return {
        "Authorization": f"OAuth {get_token()}",
    }


def download_master_file():
    """
    Получает книгу школьных данных непосредственно
    с Яндекс Диска через OAuth.
    """
    global _cached_workbook_bytes, _cached_workbook_at
    now = monotonic()
    if (
        _cached_workbook_bytes is not None
        and now - _cached_workbook_at < _WORKBOOK_CACHE_TTL_SECONDS
    ):
        return _cached_workbook_bytes

    response = requests.get(
        f"{YANDEX_API}/resources/download",
        headers=yandex_headers(),
        params={
            "path": YANDEX_FILE_PATH,
        },
        timeout=15,
    )

    if response.status_code != 200:
        raise HTTPException(
            status_code=502,
            detail="Yandex Disk download failed",
        )

    href = response.json().get("href")

    if not href:
        raise HTTPException(
            status_code=502,
            detail="Yandex Disk did not return download URL",
        )

    file_response = requests.get(
        href,
        timeout=30,
    )

    if file_response.status_code != 200:
        raise HTTPException(
            status_code=502,
            detail=f"Yandex Disk file download error: "
                   f"{file_response.status_code}",
        )

    _cached_workbook_bytes = file_response.content
    _cached_workbook_at = monotonic()
    return _cached_workbook_bytes


def load_workbook():
    """
    Скачивает актуальный Excel с Яндекс Диска
    и открывает его из памяти.
    """

    data = download_master_file()

    try:
        return openpyxl.load_workbook(
            io.BytesIO(data),
            read_only=True,
            data_only=True,
        )

    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail="Cannot read the configured school data workbook",
        )


# ============================================================
# EXCEL HELPERS
# ============================================================

def normalize_value(value: Any):
    if isinstance(value, (datetime, time)):
        return value.isoformat()

    return value


def read_sheet(sheet_name: str):
    # Enforce the allowlist here too, so future callers cannot bypass route guards.
    if sheet_name not in PUBLIC_READ_SHEETS:
        raise HTTPException(status_code=404, detail="Sheet not found")

    configured_data = load_configured_sheet(sheet_name)
    if configured_data is not None:
        return configured_data

    workbook = load_workbook()

    try:
        if sheet_name not in workbook.sheetnames:
            raise HTTPException(status_code=404, detail="Sheet not found")

        sheet = workbook[sheet_name]

        rows = sheet.iter_rows(values_only=True)

        try:
            headers = next(rows)
        except StopIteration:
            return []

        headers = [
            str(header).strip()
            if header is not None
            else None
            for header in headers
        ]

        result = []

        for row in rows:
            item = {}

            for index, header in enumerate(headers):
                if not header:
                    continue

                value = (
                    row[index]
                    if index < len(row)
                    else None
                )

                item[header] = normalize_value(value)

            if any(
                value is not None
                for value in item.values()
            ):
                result.append(item)

        return result

    finally:
        workbook.close()


# ============================================================
# ROOT
# ============================================================

@app.get("/")
def root():
    return {
        "name": "Поколение — сервер школы",
        "version": "1.0.0",
        "status": "ok",
        "source": "Yandex Disk",
    }


@app.get("/api/health")
def health():
    source = os.getenv("NAVIGATOR_DATA_SOURCE", "yandex").strip().lower()
    try:
        if source == "yandex":
            data = download_master_file()
            return {"status": "ok", "source": "yandex", "file": YANDEX_FILE_PATH, "size": len(data)}
        sample = load_configured_sheet("Classes")
        return {"status": "ok", "source": source, "sample_rows": len(sample or [])}
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(status_code=502, detail="School data source is temporarily unavailable")


# ============================================================
# SHEETS
# ============================================================

@app.get("/api/sheets")
def get_sheets():
    if os.getenv("NAVIGATOR_DATA_SOURCE", "yandex").strip().lower() in {"json", "http"}:
        return {"sheets": sorted(PUBLIC_READ_SHEETS)}
    workbook = load_workbook()
    try:
        return {"sheets": [name for name in workbook.sheetnames if name in PUBLIC_READ_SHEETS]}
    finally:
        workbook.close()


@app.get("/api/schema/{sheet_name}")
def get_schema(sheet_name: str):
    # Reject private sheet names before making any upstream request.
    if sheet_name not in PUBLIC_READ_SHEETS:
        raise HTTPException(status_code=404, detail="Sheet not found")

    if os.getenv("NAVIGATOR_DATA_SOURCE", "yandex").strip().lower() in {"json", "http"}:
        rows = load_configured_sheet(sheet_name) or []
        return {"sheet": sheet_name, "columns": list(rows[0].keys()) if rows else []}

    workbook = load_workbook()

    try:
        if sheet_name not in workbook.sheetnames:
            raise HTTPException(status_code=404, detail="Sheet not found")

        sheet = workbook[sheet_name]

        first_row = next(
            sheet.iter_rows(
                min_row=1,
                max_row=1,
                values_only=True,
            ),
            (),
        )

        columns = [
            str(value)
            for value in first_row
            if value is not None
        ]

        return {
            "sheet": sheet_name,
            "columns": columns,
        }

    finally:
        workbook.close()


# ============================================================
# CLASSES
# ============================================================

@app.get("/api/classes")
def get_classes():

    return {
        "data": read_sheet("Classes")
    }


@app.get("/api/classes/{class_id}")
def get_class(class_id: str):

    classes = read_sheet("Classes")

    for item in classes:

        if str(item.get("id")) == class_id:
            return item

    raise HTTPException(
        status_code=404,
        detail="Class not found",
    )


# ============================================================
# SCHEDULE
# ============================================================

@app.get("/api/schedule")
def get_schedule(
    class_id: str | None = Query(None),
    weekday: int | None = Query(None, ge=1, le=7),
):

    schedule = read_sheet("BaseSchedule")

    if class_id is not None:

        schedule = [
            item
            for item in schedule
            if str(item.get("class_id")) == class_id
        ]

    if weekday is not None:

        schedule = [
            item
            for item in schedule
            if str(item.get("weekday")) == str(weekday)
        ]

    schedule.sort(
        key=lambda item: (
            str(item.get("weekday") or ""),
            int(item.get("lesson_number") or 0),
        )
    )

    return {
        "data": schedule
    }


@app.get("/api/schedule/{class_id}/{weekday}")
def get_class_schedule(
    class_id: str,
    weekday: int,
):

    if weekday < 1 or weekday > 7:
        raise HTTPException(
            status_code=400,
            detail="weekday must be between 1 and 7",
        )

    schedule = read_sheet("BaseSchedule")

    result = [item
        for item in schedule
        if str(item.get("class_id")) == class_id
        and str(item.get("weekday")) == str(weekday)
    ]

    result.sort(
        key=lambda item: int(
            item.get("lesson_number") or 0
        )
    )

    return {
        "class_id": class_id,
        "weekday": weekday,
        "data": result,
    }


# ============================================================
# SUPPLEMENTS
# ============================================================

@app.get("/api/supplements")
def get_supplements(
    weekday: int | None = Query(None, ge=1, le=7),
):

    data = read_sheet("Supplements")

    if weekday is not None:

        data = [
            item
            for item in data
            if str(item.get("weekday")) == str(weekday)
        ]

    return {
        "data": data
    }


# ============================================================
# ROOMS
# ============================================================

@app.get("/api/rooms")
def get_rooms(
    floor: int | None = None,
    search: str | None = None,
):

    rooms = read_sheet("Rooms")

    if floor is not None:

        rooms = [
            item
            for item in rooms
            if str(item.get("floor")) == str(floor)
        ]

    if search:

        q = search.lower()

        rooms = [
            item
            for item in rooms
            if q in str(item.get("name") or "").lower()
            or q in str(
                item.get("description") or ""
            ).lower()
        ]

    return {
        "data": rooms
    }


# ============================================================
# PLACES
# ============================================================

@app.get("/api/places")
def get_places(
    floor: int | None = None,
    search: str | None = None,
):

    places = read_sheet("Places")

    if floor is not None:

        places = [
            item
            for item in places
            if str(item.get("floor")) == str(floor)
        ]

    if search:

        q = search.lower()

        places = [
            item
            for item in places
            if q in str(item.get("name") or "").lower()
            or q in str(
                item.get("description") or ""
            ).lower()
        ]

    return {
        "data": places
    }


# ============================================================
# ANNOUNCEMENTS
# ============================================================

@app.get("/api/announcements")
def get_announcements(
    class_id: str | None = None,
):

    data = read_sheet("Announcements")

    if class_id is not None:

        data = [
            item
            for item in data
            if (
                str(item.get("target_class_id"))
                == class_id
                or item.get("target_class_id")
                in (None, "")
            )
        ]

    data.sort(
        key=lambda item: str(
            item.get("published_at") or ""
        ),
        reverse=True,
    )

    return {
        "data": data
    }


# ============================================================
# SETTINGS
# ============================================================

@app.get("/api/settings")
def get_settings():
    # Settings may contain internal configuration and are not public API data.
    raise HTTPException(status_code=404, detail="Not found")


# ============================================================
# DEVICES
# ============================================================

@app.get("/api/devices")
def get_devices():
    # Device inventory is internal and must not be exposed without authentication.
    raise HTTPException(status_code=404, detail="Not found")


# ============================================================
# GENERIC
# ============================================================

@app.get("/api/data/{sheet_name}")
def get_sheet_data(sheet_name: str):
    # Prevent arbitrary reads such as /api/data/Admins or /api/data/AuditLog.
    if sheet_name not in PUBLIC_READ_SHEETS:
        raise HTTPException(status_code=404, detail="Sheet not found")

    return {
        "sheet": sheet_name,
        "data": read_sheet(sheet_name),
    }