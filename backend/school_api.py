"""Authenticated school API for «Поколение».

The existing workbook-backed API remains read-only. This router adds a separate,
SQLite-backed service for identities, mentor/teacher scopes, student supplements,
device registration, and announcements. Set NAVIGATOR_DB_PATH to a persistent
volume and configure a bootstrap admin before deploying.
"""
from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import secrets
import sqlite3
import time
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from fastapi import APIRouter, Depends, Header, HTTPException, Request
from pydantic import BaseModel, Field

router = APIRouter(prefix="/api/v2", tags=["school services"])
DB_PATH = Path(os.getenv("NAVIGATOR_DB_PATH", str(Path(__file__).resolve().parent / "navigator.sqlite3")))
TOKEN_SECRET = os.getenv("NAVIGATOR_TOKEN_SECRET", "")
TOKEN_TTL_SECONDS = int(os.getenv("NAVIGATOR_TOKEN_TTL_SECONDS", "28800"))
ROLES = {"admin", "student", "mentor", "teacher"}
ANNOUNCEMENT_AUDIENCES = {"all", "students", "mentors", "teachers", "class"}
MAX_BODY_TEXT = 4000


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


@contextmanager
def _db():
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(DB_PATH, timeout=10)
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA foreign_keys = ON")
    try:
        yield connection
        connection.commit()
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()


def init_db() -> None:
    with _db() as db:
        db.executescript("""
        CREATE TABLE IF NOT EXISTS users (
          id TEXT PRIMARY KEY, username TEXT NOT NULL UNIQUE,
          password_hash TEXT NOT NULL, role TEXT NOT NULL CHECK(role IN ('admin','student','mentor','teacher')),
          display_name TEXT NOT NULL, class_id TEXT, active INTEGER NOT NULL DEFAULT 1,
          created_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS student_links (
          student_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          staff_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          link_type TEXT NOT NULL CHECK(link_type IN ('mentor','teacher')),
          subject TEXT NOT NULL DEFAULT '',
          created_at TEXT NOT NULL,
          PRIMARY KEY(student_id, staff_id, link_type)
        );
        CREATE TABLE IF NOT EXISTS teacher_subject_assignments (
          student_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          staff_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          subject TEXT NOT NULL,
          created_at TEXT NOT NULL,
          PRIMARY KEY(student_id, staff_id, subject)
        );
        CREATE TABLE IF NOT EXISTS student_supplements (
          id TEXT PRIMARY KEY, student_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          title TEXT NOT NULL, weekday INTEGER, time TEXT NOT NULL DEFAULT '',
          teacher TEXT NOT NULL DEFAULT '', room TEXT NOT NULL DEFAULT '',
          status TEXT NOT NULL DEFAULT 'active', updated_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS devices (
          id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          fcm_token TEXT NOT NULL UNIQUE, platform TEXT NOT NULL DEFAULT 'unknown',
          active INTEGER NOT NULL DEFAULT 1, updated_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS announcements (
          id TEXT PRIMARY KEY, title TEXT NOT NULL, body TEXT NOT NULL,
          severity TEXT NOT NULL CHECK(severity IN ('info','warning','emergency')),
          audience TEXT NOT NULL CHECK(audience IN ('all','students','mentors','teachers','class')),
          class_id TEXT, created_by TEXT NOT NULL REFERENCES users(id),
          created_at TEXT NOT NULL, expires_at TEXT, push_status TEXT NOT NULL DEFAULT 'not_configured'
        );
        CREATE TABLE IF NOT EXISTS audit_log (
          id INTEGER PRIMARY KEY AUTOINCREMENT, actor_id TEXT, action TEXT NOT NULL,
          target_id TEXT, details_json TEXT NOT NULL DEFAULT '{}', created_at TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_links_staff ON student_links(staff_id, link_type);
        CREATE INDEX IF NOT EXISTS idx_teacher_subject_staff ON teacher_subject_assignments(staff_id, subject);
        CREATE INDEX IF NOT EXISTS idx_supplements_student ON student_supplements(student_id);
        CREATE INDEX IF NOT EXISTS idx_announcements_created ON announcements(created_at);
        """)
        # Backward-compatible migration for databases created by earlier builds.
        link_columns = {row["name"] for row in db.execute("PRAGMA table_info(student_links)").fetchall()}
        if "subject" not in link_columns:
            db.execute("ALTER TABLE student_links ADD COLUMN subject TEXT NOT NULL DEFAULT ''")
    _bootstrap_admin()


def _bootstrap_admin() -> None:
    username = os.getenv("NAVIGATOR_BOOTSTRAP_ADMIN_USERNAME", "").strip()
    password = os.getenv("NAVIGATOR_BOOTSTRAP_ADMIN_PASSWORD", "")
    if not username and not password:
        return
    if not username or len(password) < 14:
        raise RuntimeError("Bootstrap admin requires a username and a password of at least 14 characters")
    with _db() as db:
        exists = db.execute("SELECT 1 FROM users WHERE role='admin' LIMIT 1").fetchone()
        if exists:
            return
        db.execute(
            "INSERT INTO users(id,username,password_hash,role,display_name,created_at) VALUES(?,?,?,?,?,?)",
            (secrets.token_urlsafe(12), username, _hash_password(password), "admin", "School administrator", _utc_now()),
        )


def _hash_password(password: str, salt: bytes | None = None) -> str:
    salt = salt or secrets.token_bytes(16)
    digest = hashlib.scrypt(password.encode("utf-8"), salt=salt, n=2**14, r=8, p=1, dklen=32)
    return base64.urlsafe_b64encode(salt).decode().rstrip("=") + "$" + base64.urlsafe_b64encode(digest).decode().rstrip("=")


def _verify_password(password: str, stored: str) -> bool:
    try:
        salt_text, digest_text = stored.split("$", 1)
        salt = base64.urlsafe_b64decode(salt_text + "=" * (-len(salt_text) % 4))
        expected = base64.urlsafe_b64decode(digest_text + "=" * (-len(digest_text) % 4))
        actual = hashlib.scrypt(password.encode("utf-8"), salt=salt, n=2**14, r=8, p=1, dklen=len(expected))
        return hmac.compare_digest(actual, expected)
    except (ValueError, TypeError):
        return False


def _b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode().rstrip("=")


def _signing_key() -> bytes:
    if len(TOKEN_SECRET) < 32:
        raise HTTPException(status_code=503, detail="Server authentication is not configured")
    return TOKEN_SECRET.encode("utf-8")


def _make_token(user: sqlite3.Row) -> str:
    now = int(time.time())
    header = _b64(b'{"alg":"HS256","typ":"JWT"}')
    payload = _b64(json.dumps({"sub": user["id"], "role": user["role"], "iat": now, "exp": now + TOKEN_TTL_SECONDS}, separators=(",", ":")).encode())
    message = f"{header}.{payload}"
    signature = _b64(hmac.new(_signing_key(), message.encode(), hashlib.sha256).digest())
    return f"{message}.{signature}"


def _decode_token(token: str) -> dict[str, Any]:
    try:
        header, payload, signature = token.split(".")
        message = f"{header}.{payload}"
        expected = _b64(hmac.new(_signing_key(), message.encode(), hashlib.sha256).digest())
        if not hmac.compare_digest(signature, expected):
            raise ValueError("bad signature")
        claims = json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))
        if int(claims["exp"]) <= int(time.time()):
            raise ValueError("expired")
        return claims
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid or expired access token")


def current_user(authorization: str | None = Header(default=None)) -> dict[str, Any]:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Bearer token required")
    claims = _decode_token(authorization[7:].strip())
    with _db() as db:
        user = db.execute("SELECT id,username,role,display_name,class_id,active FROM users WHERE id=?", (claims.get("sub"),)).fetchone()
    if not user or not user["active"] or user["role"] != claims.get("role"):
        raise HTTPException(status_code=401, detail="Account is inactive or token is no longer valid")
    return dict(user)


def require_roles(*roles: str):
    def dependency(user: dict[str, Any] = Depends(current_user)) -> dict[str, Any]:
        if user["role"] not in roles:
            raise HTTPException(status_code=403, detail="Insufficient permissions")
        return user
    return dependency


def _audit(actor_id: str | None, action: str, target_id: str | None = None, details: dict[str, Any] | None = None) -> None:
    with _db() as db:
        db.execute("INSERT INTO audit_log(actor_id,action,target_id,details_json,created_at) VALUES(?,?,?,?,?)",
                   (actor_id, action, target_id, json.dumps(details or {}, ensure_ascii=False), _utc_now()))


def _public_user(row: sqlite3.Row | dict[str, Any]) -> dict[str, Any]:
    return {key: row[key] for key in ("id", "username", "role", "display_name", "class_id", "active") if key in row.keys()} if isinstance(row, sqlite3.Row) else {key: row.get(key) for key in ("id", "username", "role", "display_name", "class_id", "active")}


class LoginBody(BaseModel):
    username: str = Field(min_length=1, max_length=120)
    password: str = Field(min_length=1, max_length=256)


class UserCreate(BaseModel):
    username: str = Field(min_length=3, max_length=120, pattern=r"^[A-Za-z0-9_.@-]+$")
    password: str = Field(min_length=14, max_length=256)
    role: str
    display_name: str = Field(min_length=1, max_length=160)
    class_id: str | None = Field(default=None, max_length=40)


class LinkBody(BaseModel):
    student_id: str
    staff_id: str
    link_type: str
    subject: str = Field(default="", max_length=120)


class SupplementBody(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    weekday: int | None = Field(default=None, ge=1, le=7)
    time: str = Field(default="", max_length=80)
    teacher: str = Field(default="", max_length=160)
    room: str = Field(default="", max_length=80)
    status: str = Field(default="active", max_length=40)


class DeviceBody(BaseModel):
    token: str = Field(min_length=20, max_length=4096)
    platform: str = Field(default="unknown", max_length=40)


class AnnouncementBody(BaseModel):
    title: str = Field(min_length=1, max_length=180)
    body: str = Field(min_length=1, max_length=MAX_BODY_TEXT)
    severity: str = "info"
    audience: str = "all"
    class_id: str | None = Field(default=None, max_length=40)
    expires_at: str | None = Field(default=None, max_length=50)


def _can_view_student(actor: dict[str, Any], student: sqlite3.Row) -> bool:
    if actor["role"] == "admin":
        return True
    if actor["role"] == "teacher":
        with _db() as db:
            link = db.execute("SELECT 1 FROM teacher_subject_assignments WHERE student_id=? AND staff_id=?",
                              (student["id"], actor["id"])).fetchone()
        return link is not None
    if actor["role"] == "mentor":
        with _db() as db:
            link = db.execute("SELECT 1 FROM student_links WHERE student_id=? AND staff_id=? AND link_type='mentor'",
                              (student["id"], actor["id"])).fetchone()
        return link is not None
    return actor["role"] == "student" and actor["id"] == student["id"]


def _send_push(tokens: list[str], title: str, body: str, data: dict[str, str]) -> tuple[str, int]:
    if not tokens:
        return "no_registered_devices", 0
    try:
        import firebase_admin
        from firebase_admin import messaging
        if not firebase_admin._apps:
            credential_path = os.getenv("FIREBASE_CREDENTIALS_PATH", "").strip()
            if not credential_path or not Path(credential_path).is_file():
                return "firebase_not_configured", 0
            from firebase_admin import credentials
            firebase_admin.initialize_app(credentials.Certificate(credential_path))
        success_count = 0
        for offset in range(0, len(tokens), 500):
            batch = tokens[offset:offset + 500]
            message = messaging.MulticastMessage(
                notification=messaging.Notification(title=title, body=body),
                data={str(k): str(v) for k, v in data.items()},
                tokens=batch,
                android=messaging.AndroidConfig(priority="high" if data.get("severity") == "emergency" else "normal"),
            )
            response = messaging.send_each_for_multicast(message)
            success_count += response.success_count
        if success_count == len(tokens):
            return "sent", success_count
        if success_count:
            return "partial", success_count
        return "failed", 0
    except ImportError:
        return "firebase_admin_package_missing", 0
    except Exception:
        # Provider exception details can contain credential or project metadata.
        return "provider_error", 0


@router.on_event("startup")
def startup() -> None:
    init_db()


@router.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "service": "pokolenie-school-api-v2"}


@router.post("/auth/login")
def login(body: LoginBody, request: Request) -> dict[str, Any]:
    # Basic per-process throttle. Production deployments should additionally use
    # a reverse-proxy/IP rate limit and centralized throttling for multi-worker setups.
    ip = request.client.host if request.client else "unknown"
    now = time.monotonic()
    attempts = getattr(login, "_attempts", {})
    recent = [t for t in attempts.get(ip, []) if now - t < 60]
    if len(recent) >= 10:
        raise HTTPException(status_code=429, detail="Too many login attempts; retry later")
    recent.append(now)
    attempts[ip] = recent
    login._attempts = attempts
    with _db() as db:
        user = db.execute("SELECT * FROM users WHERE username=? COLLATE NOCASE", (body.username,)).fetchone()
    if not user or not user["active"] or not _verify_password(body.password, user["password_hash"]):
        _audit(None, "auth.login_failed", None, {"username": body.username[:120]})
        raise HTTPException(status_code=401, detail="Invalid username or password")
    token = _make_token(user)
    _audit(user["id"], "auth.login")
    return {"access_token": token, "token_type": "bearer", "expires_in": TOKEN_TTL_SECONDS, "user": _public_user(user)}


@router.get("/auth/me")
def me(user: dict[str, Any] = Depends(current_user)) -> dict[str, Any]:
    return {"user": user}


@router.post("/admin/users", status_code=201)
def create_user(body: UserCreate, actor: dict[str, Any] = Depends(require_roles("admin"))) -> dict[str, Any]:
    if body.role not in ROLES:
        raise HTTPException(status_code=422, detail="Unknown role")
    if body.role == "student" and not body.class_id:
        raise HTTPException(status_code=422, detail="Students must have a class_id")
    user_id = secrets.token_urlsafe(12)
    try:
        with _db() as db:
            db.execute("INSERT INTO users(id,username,password_hash,role,display_name,class_id,created_at) VALUES(?,?,?,?,?,?,?)",
                       (user_id, body.username, _hash_password(body.password), body.role, body.display_name, body.class_id, _utc_now()))
    except sqlite3.IntegrityError:
        raise HTTPException(status_code=409, detail="Username already exists")
    _audit(actor["id"], "user.created", user_id, {"role": body.role})
    return {"user": {"id": user_id, "username": body.username, "role": body.role, "display_name": body.display_name, "class_id": body.class_id, "active": 1}}


@router.post("/admin/student-links", status_code=201)
def create_student_link(body: LinkBody, actor: dict[str, Any] = Depends(require_roles("admin"))) -> dict[str, str]:
    if body.link_type not in {"mentor", "teacher"}:
        raise HTTPException(status_code=422, detail="link_type must be mentor or teacher")
    with _db() as db:
        student = db.execute("SELECT role FROM users WHERE id=? AND active=1", (body.student_id,)).fetchone()
        staff = db.execute("SELECT role FROM users WHERE id=? AND active=1", (body.staff_id,)).fetchone()
        if not student or student["role"] != "student" or not staff or staff["role"] != body.link_type:
            raise HTTPException(status_code=422, detail="Student/staff roles do not match the requested link")
        if body.link_type == "teacher":
            if not body.subject.strip():
                raise HTTPException(status_code=422, detail="subject is required for teacher assignments")
            db.execute("INSERT OR IGNORE INTO teacher_subject_assignments(student_id,staff_id,subject,created_at) VALUES(?,?,?,?)",
                       (body.student_id, body.staff_id, body.subject.strip(), _utc_now()))
        else:
            db.execute("INSERT OR IGNORE INTO student_links(student_id,staff_id,link_type,subject,created_at) VALUES(?,?,?,?,?)",
                       (body.student_id, body.staff_id, body.link_type, "", _utc_now()))
    _audit(actor["id"], "student.linked", body.student_id, {"staff_id": body.staff_id, "link_type": body.link_type, "subject": body.subject.strip()})
    return {"status": "linked", "student_id": body.student_id, "staff_id": body.staff_id, "link_type": body.link_type, "subject": body.subject.strip()}


@router.get("/students")
def list_students(actor: dict[str, Any] = Depends(require_roles("admin", "mentor", "teacher"))) -> dict[str, Any]:
    with _db() as db:
        if actor["role"] == "admin":
            rows = db.execute("SELECT id,username,role,display_name,class_id,active FROM users WHERE role='student' AND active=1 ORDER BY display_name").fetchall()
        elif actor["role"] == "teacher":
            rows = db.execute("SELECT DISTINCT u.id,u.username,u.role,u.display_name,u.class_id,u.active FROM users u JOIN teacher_subject_assignments l ON l.student_id=u.id WHERE u.role='student' AND u.active=1 AND l.staff_id=? ORDER BY u.display_name",
                              (actor["id"],)).fetchall()
        else:
            rows = db.execute("SELECT u.id,u.username,u.role,u.display_name,u.class_id,u.active FROM users u JOIN student_links l ON l.student_id=u.id WHERE u.role='student' AND u.active=1 AND l.staff_id=? AND l.link_type='mentor' ORDER BY u.display_name",
                              (actor["id"],)).fetchall()
    return {"data": [dict(row) for row in rows]}


@router.get("/students/{student_id}")
def get_student(student_id: str, actor: dict[str, Any] = Depends(require_roles("admin", "mentor", "teacher", "student"))) -> dict[str, Any]:
    with _db() as db:
        student = db.execute("SELECT id,username,role,display_name,class_id,active FROM users WHERE id=? AND role='student' AND active=1", (student_id,)).fetchone()
        if not student or not _can_view_student(actor, student):
            # Deliberately use the same response for absent and unauthorized student records.
            raise HTTPException(status_code=404, detail="Student not found")
        if actor["role"] == "teacher":
            # A subject teacher can see the student record and only their own
            # subject assignment, not the student's full private DOP schedule.
            supplements = []
            links = db.execute(
                "SELECT u.id,u.display_name,u.role,l.subject FROM teacher_subject_assignments l "
                "JOIN users u ON u.id=l.staff_id WHERE l.student_id=? AND l.staff_id=? AND u.active=1",
                (student_id, actor["id"]),
            ).fetchall()
        else:
            supplements = db.execute(
                "SELECT id,title,weekday,time,teacher,room,status,updated_at FROM student_supplements "
                "WHERE student_id=? ORDER BY weekday,time", (student_id,),
            ).fetchall()
            mentor_links = db.execute(
                "SELECT u.id,u.display_name,u.role,'' AS subject FROM student_links l "
                "JOIN users u ON u.id=l.staff_id WHERE l.student_id=? AND u.active=1",
                (student_id,),
            ).fetchall()
            teacher_links = db.execute(
                "SELECT u.id,u.display_name,u.role,l.subject FROM teacher_subject_assignments l "
                "JOIN users u ON u.id=l.staff_id WHERE l.student_id=? AND u.active=1",
                (student_id,),
            ).fetchall()
            links = list(mentor_links) + list(teacher_links)
    return {"student": dict(student), "supplements": [dict(x) for x in supplements], "staff": [dict(x) for x in links]}


@router.post("/admin/students/{student_id}/supplements", status_code=201)
def add_student_supplement(student_id: str, body: SupplementBody, actor: dict[str, Any] = Depends(require_roles("admin"))) -> dict[str, Any]:
    supplement_id = secrets.token_urlsafe(12)
    with _db() as db:
        student = db.execute("SELECT id FROM users WHERE id=? AND role='student' AND active=1", (student_id,)).fetchone()
        if not student:
            raise HTTPException(status_code=404, detail="Student not found")
        db.execute("INSERT INTO student_supplements(id,student_id,title,weekday,time,teacher,room,status,updated_at) VALUES(?,?,?,?,?,?,?,?,?)",
                   (supplement_id, student_id, body.title, body.weekday, body.time, body.teacher, body.room, body.status, _utc_now()))
    _audit(actor["id"], "student.supplement_created", student_id, {"supplement_id": supplement_id})
    return {"id": supplement_id, "student_id": student_id, **body.model_dump(), "updated_at": _utc_now()}


@router.post("/devices/register", status_code=201)
def register_device(body: DeviceBody, actor: dict[str, Any] = Depends(current_user)) -> dict[str, str]:
    # FCM tokens are private device identifiers: never return them from APIs or logs.
    with _db() as db:
        db.execute("INSERT INTO devices(id,user_id,fcm_token,platform,active,updated_at) VALUES(?,?,?,?,1,?) ON CONFLICT(fcm_token) DO UPDATE SET user_id=excluded.user_id,platform=excluded.platform,active=1,updated_at=excluded.updated_at",
                   (secrets.token_urlsafe(12), actor["id"], body.token, body.platform, _utc_now()))
    _audit(actor["id"], "device.registered", None, {"platform": body.platform})
    return {"status": "registered"}


@router.get("/announcements")
def list_announcements(actor: dict[str, Any] = Depends(current_user)) -> dict[str, Any]:
    with _db() as db:
        rows = db.execute("SELECT * FROM announcements ORDER BY created_at DESC LIMIT 100").fetchall()
    visible = []
    for row in rows:
        audience_role = {"students": "student"}.get(row["audience"], row["audience"])
        if row["audience"] == "all" or audience_role == actor["role"]:
            visible.append(row)
        elif row["audience"] == "class" and actor.get("class_id") and row["class_id"] == actor["class_id"]:
            visible.append(row)
        elif actor["role"] == "admin":
            visible.append(row)
    return {"data": [{k: row[k] for k in ("id","title","body","severity","audience","class_id","created_by","created_at","expires_at","push_status")} for row in visible]}


@router.post("/admin/announcements", status_code=201)
def create_announcement(body: AnnouncementBody, actor: dict[str, Any] = Depends(require_roles("admin"))) -> dict[str, Any]:
    if body.severity not in {"info", "warning", "emergency"}:
        raise HTTPException(status_code=422, detail="severity must be info, warning or emergency")
    if body.audience not in ANNOUNCEMENT_AUDIENCES:
        raise HTTPException(status_code=422, detail="Unsupported audience")
    if body.audience == "class" and not body.class_id:
        raise HTTPException(status_code=422, detail="class_id is required for class audience")
    if body.expires_at:
        try:
            datetime.fromisoformat(body.expires_at.replace("Z", "+00:00"))
        except ValueError:
            raise HTTPException(status_code=422, detail="expires_at must be an ISO-8601 timestamp")
    announcement_id = secrets.token_urlsafe(12)
    created_at = _utc_now()
    with _db() as db:
        db.execute("INSERT INTO announcements(id,title,body,severity,audience,class_id,created_by,created_at,expires_at) VALUES(?,?,?,?,?,?,?,?,?)",
                   (announcement_id, body.title, body.body, body.severity, body.audience, body.class_id, actor["id"], created_at, body.expires_at))
        if body.audience == "all":
            device_rows = db.execute("SELECT fcm_token FROM devices WHERE active=1").fetchall()
        elif body.audience == "class":
            device_rows = db.execute("SELECT d.fcm_token FROM devices d JOIN users u ON u.id=d.user_id WHERE d.active=1 AND u.class_id=?", (body.class_id,)).fetchall()
        else:
            target_role = {"students": "student"}.get(body.audience, body.audience)
            device_rows = db.execute("SELECT d.fcm_token FROM devices d JOIN users u ON u.id=d.user_id WHERE d.active=1 AND u.role=?", (target_role,)).fetchall()
        tokens = [row["fcm_token"] for row in device_rows]
    push_status, sent_count = _send_push(tokens, body.title, body.body, {"announcement_id": announcement_id, "severity": body.severity})
    with _db() as db:
        db.execute("UPDATE announcements SET push_status=? WHERE id=?", (push_status, announcement_id))
        if push_status in {"sent", "partial", "failed"}:
            # Token-level response handling is intentionally isolated to avoid
            # persisting provider details or exposing device tokens in the audit log.
            pass
    _audit(actor["id"], "announcement.created", announcement_id, {"severity": body.severity, "audience": body.audience, "push_status": push_status, "sent_count": sent_count})
    return {"id": announcement_id, "title": body.title, "body": body.body, "severity": body.severity, "audience": body.audience, "class_id": body.class_id, "created_at": created_at, "push_status": push_status, "sent_count": sent_count}


@router.get("/admin/audit")
def read_audit(limit: int = 100, actor: dict[str, Any] = Depends(require_roles("admin"))) -> dict[str, Any]:
    limit = max(1, min(limit, 500))
    with _db() as db:
        rows = db.execute("SELECT id,actor_id,action,target_id,details_json,created_at FROM audit_log ORDER BY id DESC LIMIT ?", (limit,)).fetchall()
    return {"data": [dict(row) for row in rows]}

@router.get("/teachers/me/subjects")
def teacher_subject_roster(actor: dict[str, Any] = Depends(require_roles("teacher"))) -> dict[str, Any]:
    """Return only student records explicitly assigned to this teacher, grouped by subject."""
    with _db() as db:
        rows = db.execute(
            "SELECT l.subject,u.id,u.display_name,u.class_id FROM teacher_subject_assignments l "
            "JOIN users u ON u.id=l.student_id WHERE l.staff_id=? "
            "AND u.role='student' AND u.active=1 ORDER BY l.subject,u.display_name",
            (actor["id"],),
        ).fetchall()
    return {"data": [dict(row) for row in rows]}