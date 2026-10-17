"""Role/position extensions for school leadership and operational staff.

Base login roles stay backward-compatible; a separate position and explicit scope
grant additional school duties without making every deputy/teacher an administrator.
"""
from __future__ import annotations

import asyncio
import hashlib
import os
import re
import secrets
from datetime import datetime, timezone
from typing import Any

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from . import school_api as core

router = APIRouter(prefix="/api/v2", tags=["school roles and management"])

POSITIONS = {
    "director", "deputy", "homeroom_teacher", "dop_coordinator",
    "mentor_coordinator", "teacher", "mentor", "librarian",
}
PERMISSIONS = {
    "director": {"dashboard.read", "students.read_all", "dop.read_all", "dop.manage",
                 "staff.read", "staff.manage", "assignments.manage", "announcements.publish",
                 "notifications.publish", "audit.read"},
    "deputy": {"dashboard.read", "students.read_all", "dop.read_all", "dop.manage",
               "staff.read", "assignments.manage", "announcements.publish",
               "notifications.publish", "audit.read"},
    "homeroom_teacher": {"dashboard.read", "students.read_class", "dop.read_class",
                         "announcements.publish_class", "notifications.publish_class"},
    "dop_coordinator": {"dashboard.read", "students.read_directory", "dop.read_all", "dop.manage",
                        "notifications.publish_class"},
    "mentor_coordinator": {"dashboard.read", "students.read_directory", "assignments.manage"},
    "teacher": {"students.read_assigned", "notifications.publish_assigned"},
    "mentor": {"students.read_assigned", "dop.read_assigned"},
    "librarian": {"students.read_directory"},
}
ADMIN_PERMISSIONS = {"*"}


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _init() -> None:
    with core._db() as db:
        db.executescript("""
        CREATE TABLE IF NOT EXISTS staff_positions (
          user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
          position TEXT NOT NULL,
          scope_class TEXT,
          assigned_by TEXT REFERENCES users(id),
          updated_at TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_staff_positions_position ON staff_positions(position,scope_class);
        CREATE TABLE IF NOT EXISTS school_sync_runs (
          id INTEGER PRIMARY KEY AUTOINCREMENT, source TEXT NOT NULL,
          imported INTEGER NOT NULL, skipped INTEGER NOT NULL, created_at TEXT NOT NULL,
          result_json TEXT NOT NULL DEFAULT '{}'
        );
        CREATE TABLE IF NOT EXISTS schedule_teacher_aliases (
          source_name TEXT PRIMARY KEY COLLATE NOCASE,
          staff_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          created_by TEXT REFERENCES users(id), created_at TEXT NOT NULL
        );
        """)


_auto_sync_task: asyncio.Task | None = None


@router.on_event("startup")
async def init_roles() -> None:
    global _auto_sync_task
    _init()
    interval = int(os.getenv("NAVIGATOR_AUTO_SYNC_INTERVAL_SECONDS", "300"))
    if interval > 0 and (_auto_sync_task is None or _auto_sync_task.done()):
        _auto_sync_task = asyncio.create_task(_auto_sync_loop())


async def _auto_sync_loop() -> None:
    while True:
        interval = max(60, int(os.getenv("NAVIGATOR_AUTO_SYNC_INTERVAL_SECONDS", "300")))
        try:
            with core._db() as db:
                sync_actor = db.execute(
                    "SELECT u.id,u.role FROM users u LEFT JOIN staff_positions p ON p.user_id=u.id "
                    "WHERE u.active=1 AND (u.role='admin' OR p.position IN ('director','deputy')) "
                    "ORDER BY CASE WHEN u.role='admin' THEN 0 ELSE 1 END,u.created_at LIMIT 1"
                ).fetchone()
            if sync_actor:
                actor = {"id": sync_actor["id"], "role": sync_actor["role"]}
                await asyncio.to_thread(sync_supplements, actor)
                await asyncio.to_thread(sync_teacher_assignments, actor)
        except Exception:
            # Keep the API alive if an external data source is unavailable.
            pass
        await asyncio.sleep(interval)


class ManagedUserCreate(BaseModel):
    username: str = Field(min_length=3, max_length=120, pattern=r"^[A-Za-z0-9_.@-]+$")
    password: str = Field(min_length=14, max_length=256)
    role: str
    display_name: str = Field(min_length=1, max_length=160)
    class_id: str | None = Field(default=None, max_length=40)


class PositionBody(BaseModel):
    username: str = Field(min_length=1, max_length=120)
    position: str
    scope_class: str | None = Field(default=None, max_length=40)


class ActiveBody(BaseModel):
    active: bool


class UserPatch(BaseModel):
    display_name: str | None = Field(default=None, min_length=1, max_length=160)
    class_id: str | None = Field(default=None, max_length=40)
    active: bool | None = None


class AssignmentBody(BaseModel):
    student_id: str = Field(min_length=1, max_length=128)
    staff_id: str = Field(min_length=1, max_length=128)
    assignment_type: str
    subject: str = Field(default="", max_length=120)


def _position(user_id: str) -> tuple[str | None, str | None]:
    with core._db() as db:
        row = db.execute("SELECT position,scope_class FROM staff_positions WHERE user_id=?", (user_id,)).fetchone()
    return (row["position"], row["scope_class"]) if row else (None, None)


def _has(actor: dict[str, Any], permission: str) -> bool:
    if actor.get("role") == "admin":
        return True
    position, _ = _position(actor["id"])
    grants = PERMISSIONS.get(position or "", set())
    return "*" in grants or permission in grants


def require_permission(permission: str):
    def dependency(actor: dict[str, Any] = Depends(core.current_user)) -> dict[str, Any]:
        if not _has(actor, permission):
            raise HTTPException(status_code=403, detail="Insufficient school-role permissions")
        return actor
    return dependency


def _require_position_actor(actor: dict[str, Any], permission: str) -> tuple[str, str | None]:
    position, scope_class = _position(actor["id"])
    if actor.get("role") != "admin" and not _has(actor, permission):
        raise HTTPException(status_code=403, detail="Insufficient school-role permissions")
    return position or ("administrator" if actor.get("role") == "admin" else actor.get("role", "")), scope_class


@router.get("/public/config")
def public_config() -> dict[str, Any]:
    # Only public client configuration is exposed here. No secrets, service-account
    # JSON, API tokens, or private school data are returned.
    firebase = {
        "api_key": __import__("os").getenv("FIREBASE_WEB_API_KEY", "").strip(),
        "app_id": __import__("os").getenv("FIREBASE_ANDROID_APP_ID", "").strip(),
        "messaging_sender_id": __import__("os").getenv("FIREBASE_MESSAGING_SENDER_ID", "").strip(),
        "project_id": __import__("os").getenv("FIREBASE_PROJECT_ID", "").strip(),
    }
    os = __import__("os")
    credential_path = os.getenv("FIREBASE_CREDENTIALS_PATH", "").strip()
    credential_ready = bool(os.getenv("FIREBASE_CREDENTIALS_JSON_BASE64", "").strip()) or bool(credential_path and os.path.isfile(credential_path))
    firebase_enabled = all(firebase.values()) and credential_ready and os.getenv("NAVIGATOR_ENABLE_FIREBASE", "false").strip().lower() in {"1", "true", "yes", "on"}
    issuer = os.getenv("NAVIGATOR_OIDC_ISSUER", "").strip()
    client_id = os.getenv("NAVIGATOR_OIDC_CLIENT_ID", "").strip()
    redirect_uri = os.getenv("NAVIGATOR_OIDC_REDIRECT_URI", "ru.pokolenie.navigator:/oauthredirect").strip()
    return {
        "school_name": os.getenv("NAVIGATOR_SCHOOL_NAME", "Школа «Поколение»"),
        "api_version": "v2",
        "sso": {"enabled": bool(issuer and client_id and redirect_uri), "issuer": issuer,
                "client_id": client_id, "redirect_uri": redirect_uri,
                "scopes": ["openid", "profile", "email"]},
        "firebase": {"enabled": firebase_enabled, **(firebase if firebase_enabled else {})},
    }


@router.get("/auth/permissions")
def my_permissions(actor: dict[str, Any] = Depends(core.current_user)) -> dict[str, Any]:
    position, scope_class = _position(actor["id"])
    grants = sorted(PERMISSIONS.get(position or "", set()))
    if actor.get("role") == "admin":
        grants = ["*"]
    return {"user": actor, "position": position, "scope_class": scope_class, "permissions": grants}


@router.delete("/admin/staff-positions/{username}")
def remove_position(username: str, actor: dict[str, Any] = Depends(core.current_user)) -> dict[str, str]:
    actor_position, _ = _position(actor["id"])
    if actor["role"] != "admin" and actor_position not in {"director", "deputy"}:
        raise HTTPException(status_code=403, detail="School leadership permission required")
    with core._db() as db:
        target = db.execute(
            "SELECT u.id,p.position FROM users u LEFT JOIN staff_positions p ON p.user_id=u.id "
            "WHERE u.username=? COLLATE NOCASE AND u.active=1", (username,)
        ).fetchone()
        if not target:
            raise HTTPException(status_code=404, detail="Staff account not found")
        if actor["role"] != "admin" and target["id"] == actor["id"]:
            raise HTTPException(status_code=403, detail="School leadership cannot remove its own position")
        if actor["role"] != "admin" and target["position"] in {"director", "deputy"}:
            raise HTTPException(status_code=403, detail="Only an administrator can remove top leadership positions")
        db.execute("DELETE FROM staff_positions WHERE user_id=?", (target["id"],))
    core._audit(actor["id"], "staff.position_removed", target["id"], {"previous_position": target["position"]})
    return {"status": "removed"}


@router.get("/admin/users")
def list_users(actor: dict[str, Any] = Depends(require_permission("staff.read"))) -> dict[str, Any]:
    with core._db() as db:
        rows = db.execute(
            "SELECT u.id,u.username,u.role,u.display_name,u.class_id,u.active,u.created_at,"
            "p.position,p.scope_class FROM users u LEFT JOIN staff_positions p ON p.user_id=u.id "
            "ORDER BY u.role,u.display_name LIMIT 2000"
        ).fetchall()
    return {"data": [dict(row) for row in rows]}


@router.post("/management/users", status_code=201)
def management_create_user(body: ManagedUserCreate,
                           actor: dict[str, Any] = Depends(require_permission("staff.manage"))) -> dict[str, Any]:
    # Director/deputy accounts can create operational accounts; the highest
    # leadership position itself remains assignable only by a base admin.
    position, _ = _position(actor["id"])
    if actor["role"] != "admin" and position not in {"director", "deputy"}:
        raise HTTPException(status_code=403, detail="Only school leadership can create accounts")
    if actor["role"] != "admin" and body.role == "admin":
        raise HTTPException(status_code=403, detail="Only an existing administrator can create another administrator")
    result = core.create_user(
        core.UserCreate(username=body.username, password=body.password, role=body.role,
                        display_name=body.display_name, class_id=body.class_id),
        actor,
    )
    return result


@router.patch("/admin/users/{user_id}")
def patch_user(user_id: str, body: UserPatch,
               actor: dict[str, Any] = Depends(require_permission("staff.manage"))) -> dict[str, Any]:
    changes = body.model_dump(exclude_unset=True)
    if not changes:
        raise HTTPException(status_code=422, detail="No fields to update")
    with core._db() as db:
        target_role = db.execute("SELECT role FROM users WHERE id=?", (user_id,)).fetchone()
    if target_role and target_role["role"] == "admin" and actor["role"] != "admin":
        raise HTTPException(status_code=403, detail="Only an existing administrator can modify administrator accounts")
    if "active" in changes and not changes["active"]:
        with core._db() as db:
            target = db.execute("SELECT role FROM users WHERE id=?", (user_id,)).fetchone()
            if target and target["role"] == "admin":
                admins = db.execute("SELECT COUNT(*) AS n FROM users WHERE role='admin' AND active=1").fetchone()["n"]
                if admins <= 1:
                    raise HTTPException(status_code=409, detail="Cannot deactivate the last active administrator")
    fields = []
    values: list[Any] = []
    for key in ("display_name", "class_id", "active"):
        if key in changes:
            fields.append(f"{key}=?")
            values.append(int(changes[key]) if key == "active" else changes[key])
    deactivating = "active" in changes and not changes["active"]
    if deactivating:
        fields.append("token_version=token_version+1")
    with core._db() as db:
        exists = db.execute("SELECT id FROM users WHERE id=?", (user_id,)).fetchone()
        if not exists:
            raise HTTPException(status_code=404, detail="Account not found")
        db.execute(f"UPDATE users SET {','.join(fields)} WHERE id=?", (*values, user_id))
        if deactivating:
            db.execute("UPDATE refresh_tokens SET revoked_at=?,last_used_at=? WHERE user_id=? AND revoked_at IS NULL",
                       (_now(), _now(), user_id))
            db.execute("UPDATE devices SET active=0,updated_at=? WHERE user_id=?",
                       (_now(), user_id))
        row = db.execute(
            "SELECT u.id,u.username,u.role,u.display_name,u.class_id,u.active,p.position,p.scope_class "
            "FROM users u LEFT JOIN staff_positions p ON p.user_id=u.id WHERE u.id=?", (user_id,)
        ).fetchone()
    core._audit(actor["id"], "user.updated", user_id, {"fields": sorted(changes)})
    return {"user": dict(row)}


@router.put("/admin/staff-positions")
def assign_position(body: PositionBody,
                    actor: dict[str, Any] = Depends(core.current_user)) -> dict[str, Any]:
    actor_position, _ = _position(actor["id"])
    if actor["role"] != "admin" and actor_position not in {"director", "deputy"}:
        raise HTTPException(status_code=403, detail="School leadership permission required")
    if actor["role"] != "admin" and body.position in {"director", "deputy"}:
        raise HTTPException(status_code=403, detail="Only an existing administrator can assign top leadership positions")
    if body.position not in POSITIONS:
        raise HTTPException(status_code=422, detail="Unsupported staff position")
    if body.position == "homeroom_teacher" and not body.scope_class:
        raise HTTPException(status_code=422, detail="Homeroom teacher requires scope_class")
    with core._db() as db:
        user = db.execute("SELECT id,role,active FROM users WHERE username=? COLLATE NOCASE", (body.username,)).fetchone()
        if not user or not user["active"]:
            raise HTTPException(status_code=404, detail="Active account not found")
        if user["role"] not in {"teacher", "mentor", "admin"}:
            raise HTTPException(status_code=422, detail="Only staff accounts can receive school positions")
        mentor_positions = {"mentor", "mentor_coordinator"}
        teacher_positions = {"teacher", "homeroom_teacher", "dop_coordinator", "librarian"}
        leadership_positions = {"director", "deputy"}
        if body.position in mentor_positions and user["role"] not in {"mentor", "admin"}:
            raise HTTPException(status_code=422, detail="Mentor positions require a mentor or administrator account")
        if body.position in teacher_positions and user["role"] not in {"teacher", "admin"}:
            raise HTTPException(status_code=422, detail="This position requires a teacher or administrator account")
        if body.position in leadership_positions and user["role"] not in {"teacher", "admin"}:
            raise HTTPException(status_code=422, detail="School leadership positions require a teacher or administrator account")
        if actor["role"] != "admin" and user["id"] == actor["id"]:
            raise HTTPException(status_code=403, detail="School leadership cannot change its own position")
        db.execute(
            "INSERT INTO staff_positions(user_id,position,scope_class,assigned_by,updated_at) VALUES(?,?,?,?,?) "
            "ON CONFLICT(user_id) DO UPDATE SET position=excluded.position,scope_class=excluded.scope_class,"
            "assigned_by=excluded.assigned_by,updated_at=excluded.updated_at",
            (user["id"], body.position, body.scope_class, actor["id"], _now()),
        )
    core._audit(actor["id"], "staff.position_assigned", user["id"], {"position": body.position, "scope_class": body.scope_class})
    return {"status": "assigned", "user_id": user["id"], "position": body.position, "scope_class": body.scope_class}


@router.delete("/admin/staff-positions/by-id/{user_id}")
def remove_position_by_id(user_id: str, actor: dict[str, Any] = Depends(core.require_roles("admin"))) -> dict[str, str]:
    with core._db() as db:
        cur = db.execute("DELETE FROM staff_positions WHERE user_id=?", (user_id,))
    if not cur.rowcount:
        raise HTTPException(status_code=404, detail="Position assignment not found")
    core._audit(actor["id"], "staff.position_removed", user_id)
    return {"status": "removed"}


@router.get("/management/staff")
def management_staff(actor: dict[str, Any] = Depends(require_permission("assignments.manage"))) -> dict[str, Any]:
    with core._db() as db:
        rows = db.execute(
            "SELECT u.id,u.username,u.role,u.display_name,u.class_id,u.active,p.position,p.scope_class "
            "FROM users u LEFT JOIN staff_positions p ON p.user_id=u.id "
            "WHERE u.active=1 AND u.role IN ('teacher','mentor','admin') ORDER BY u.display_name LIMIT 1000"
        ).fetchall()
    return {"data": [dict(row) for row in rows]}


@router.get("/management/audit")
def management_audit(limit: int = 100,
                     actor: dict[str, Any] = Depends(require_permission("audit.read"))) -> dict[str, Any]:
    limit = max(1, min(limit, 500))
    with core._db() as db:
        rows = db.execute(
            "SELECT id,actor_id,action,target_id,details_json,created_at FROM audit_log ORDER BY id DESC LIMIT ?",
            (limit,)
        ).fetchall()
    return {"data": [dict(row) for row in rows]}


def _normalized_row(row: dict[str, Any]) -> dict[str, Any]:
    def key(value: Any) -> str:
        return re.sub(r"[^a-z0-9а-я]+", "_", str(value or "").strip().lower())
    return {key(k): v for k, v in row.items()}


def _field(row: dict[str, Any], *names: str) -> str:
    for name in names:
        value = row.get(name)
        if value is not None and str(value).strip():
            return str(value).strip()
    return ""


def _weekday(value: str) -> int | None:
    raw = value.strip().lower()
    try:
        number = int(float(raw))
        return number if 1 <= number <= 7 else None
    except ValueError:
        pass
    days = {
        "пн": 1, "понедельник": 1, "mon": 1, "monday": 1,
        "вт": 2, "вторник": 2, "tue": 2, "tuesday": 2,
        "ср": 3, "среда": 3, "wed": 3, "wednesday": 3,
        "чт": 4, "четверг": 4, "thu": 4, "thursday": 4,
        "пт": 5, "пятница": 5, "fri": 5, "friday": 5,
        "сб": 6, "суббота": 6, "sat": 6, "saturday": 6,
        "вс": 7, "воскресенье": 7, "sun": 7, "sunday": 7,
    }
    return days.get(raw)


class TeacherAliasBody(BaseModel):
    source_name: str = Field(min_length=1, max_length=160)
    staff_id: str = Field(min_length=1, max_length=128)


def _class_key(value: str) -> str:
    lookalikes = str.maketrans({
        "А": "A", "В": "B", "С": "C", "Е": "E", "Н": "H",
        "К": "K", "М": "M", "О": "O", "Р": "P", "Т": "T",
        "Х": "X", "У": "Y",
    })
    return str(value or "").strip().upper().replace(" ", "").translate(lookalikes)


@router.get("/management/sync/teacher-aliases")
def list_teacher_aliases(actor: dict[str, Any] = Depends(require_permission("assignments.manage"))) -> dict[str, Any]:
    with core._db() as db:
        rows = db.execute(
            "SELECT a.source_name,a.staff_id,u.display_name,u.username FROM schedule_teacher_aliases a "
            "JOIN users u ON u.id=a.staff_id ORDER BY a.source_name"
        ).fetchall()
    return {"data": [dict(row) for row in rows]}


@router.put("/admin/schedule-teacher-aliases")
def set_teacher_alias(body: TeacherAliasBody,
                      actor: dict[str, Any] = Depends(core.current_user)) -> dict[str, Any]:
    if actor["role"] != "admin" and not _has(actor, "assignments.manage"):
        raise HTTPException(status_code=403, detail="Assignment management permission required")
    source_name = body.source_name.strip()
    with core._db() as db:
        staff = db.execute("SELECT id,role,active FROM users WHERE id=?", (body.staff_id,)).fetchone()
        if not staff or not staff["active"] or staff["role"] != "teacher":
            raise HTTPException(status_code=422, detail="Alias must map to an active teacher account")
        db.execute(
            "INSERT INTO schedule_teacher_aliases(source_name,staff_id,created_by,created_at) VALUES(?,?,?,?) "
            "ON CONFLICT(source_name) DO UPDATE SET staff_id=excluded.staff_id,created_by=excluded.created_by,created_at=excluded.created_at",
            (source_name, body.staff_id, actor["id"], _now())
        )
    core._audit(actor["id"], "schedule.teacher_alias_set", body.staff_id, {"source_name": source_name})
    return {"status": "saved", "source_name": source_name, "staff_id": body.staff_id}


@router.post("/management/sync/teacher-assignments")
def sync_teacher_assignments(actor: dict[str, Any] = Depends(require_permission("assignments.manage"))) -> dict[str, Any]:
    """Rebuild only schedule-derived teacher/student/subject links from the configured source."""
    from .main import read_sheet

    raw_rows = read_sheet("BaseSchedule")
    class_rows = read_sheet("Classes")
    if not isinstance(raw_rows, list) or not isinstance(class_rows, list):
        raise HTTPException(status_code=502, detail="Schedule source did not return valid rows")
    class_aliases: dict[str, str] = {}
    for raw_class in class_rows:
        if not isinstance(raw_class, dict):
            continue
        row = _normalized_row(raw_class)
        class_id = _field(row, "id", "class_id", "code")
        class_name = _field(row, "name", "class_name", "title", "class", "класс")
        if class_name:
            class_aliases[_class_key(class_name)] = class_name
            if class_id:
                class_aliases[_class_key(class_id)] = class_name

    with core._db() as db:
        students = [dict(row) for row in db.execute(
            "SELECT id,display_name,username,class_id FROM users WHERE role='student' AND active=1"
        ).fetchall()]
        teachers = [dict(row) for row in db.execute(
            "SELECT id,display_name,username FROM users WHERE role='teacher' AND active=1"
        ).fetchall()]
        aliases = {str(row["source_name"]).strip().casefold(): row["staff_id"]
                   for row in db.execute("SELECT source_name,staff_id FROM schedule_teacher_aliases").fetchall()}

    teachers_by_name: dict[str, str] = {}
    for teacher in teachers:
        for value in (teacher["username"], teacher["display_name"]):
            if value:
                teachers_by_name[str(value).strip().casefold()] = teacher["id"]

    assignment_keys: set[tuple[str, str, str]] = set()
    skipped = 0
    for raw in raw_rows:
        if not isinstance(raw, dict):
            skipped += 1
            continue
        row = _normalized_row(raw)
        class_ref = _field(row, "class_id", "class", "класс_id", "класс")
        class_label = _field(row, "class_name", "class_label", "class_display_name")
        class_name = class_label or class_aliases.get(_class_key(class_ref), class_ref)
        subject = _field(row, "subject", "discipline", "lesson", "предмет", "дисциплина")
        source_teacher = _field(row, "teacher", "teacher_name", "educator", "педагог", "учитель")
        if subject and not source_teacher:
            suffix = re.search(r"\s+([А-ЯЁ][а-яё-]+\s+[А-ЯЁ]\.[А-ЯЁ]\.(?:,\s*[А-ЯЁ][а-яё-]+\s+[А-ЯЁ]\.[А-ЯЁ]\.)?)\s*$", subject)
            if suffix:
                source_teacher = suffix.group(1).strip()
                subject = subject[:suffix.start()].strip()
        if not class_name or not subject or not source_teacher:
            skipped += 1
            continue
        teacher_ids = {
            staff_id for teacher_name in re.split(r"[,;]+", source_teacher)
            if (staff_id := (aliases.get(teacher_name.strip().casefold()) or teachers_by_name.get(teacher_name.strip().casefold())))
        }
        if not teacher_ids:
            skipped += 1
            continue
        class_keys = {_class_key(class_name), _class_key(class_ref)}
        matched = [student for student in students if _class_key(str(student.get("class_id") or "")) in class_keys]
        if not matched:
            skipped += 1
            continue
        for student in matched:
            for teacher_id in teacher_ids:
                assignment_keys.add((student["id"], teacher_id, subject))

    source_name = __import__("os").getenv("NAVIGATOR_DATA_SOURCE", "yandex").strip().lower()
    if not assignment_keys:
        with core._db() as db:
            db.execute(
                "INSERT INTO school_sync_runs(source,imported,skipped,created_at,result_json) VALUES(?,?,?,?,?)",
                (source_name + ":teacher_assignments", 0, skipped, _now(),
                 json.dumps({"sheet": "BaseSchedule", "note": "no matching teacher/student records"}, ensure_ascii=False))
            )
        core._audit(actor["id"], "school_data.teacher_assignments_sync_empty", None,
                    {"source": source_name, "skipped": skipped})
        return {"status": "no_assignments_imported", "rows_seen": len(raw_rows), "imported": 0,
                "skipped": skipped, "note": "No matching teacher/student records found; previous schedule assignments were preserved."}
    with core._db() as db:
        db.execute("DELETE FROM teacher_subject_assignments WHERE source_key LIKE 'schedule:%'")
        for student_id, teacher_id, subject in sorted(assignment_keys):
            key_data = json.dumps([student_id, teacher_id, subject], ensure_ascii=False, separators=(",", ":"))
            source_key = "schedule:" + hashlib.sha256(key_data.encode()).hexdigest()
            db.execute(
                "INSERT INTO teacher_subject_assignments(student_id,staff_id,subject,created_at,source_key) VALUES(?,?,?,?,?) "
                "ON CONFLICT(student_id,staff_id,subject) DO UPDATE SET created_at=excluded.created_at,source_key=excluded.source_key",
                (student_id, teacher_id, subject, _now(), source_key)
            )
        db.execute(
            "INSERT INTO school_sync_runs(source,imported,skipped,created_at,result_json) VALUES(?,?,?,?,?)",
            (source_name + ":teacher_assignments", len(assignment_keys), skipped, _now(),
             json.dumps({"sheet": "BaseSchedule"}, ensure_ascii=False))
        )
    core._audit(actor["id"], "school_data.teacher_assignments_synced", None,
                {"source": source_name, "imported": len(assignment_keys), "skipped": skipped})
    return {"status": "completed", "source": source_name, "rows_seen": len(raw_rows),
            "imported": len(assignment_keys), "skipped": skipped}


@router.post("/management/sync/supplements")
def sync_supplements(actor: dict[str, Any] = Depends(require_permission("dop.manage"))) -> dict[str, Any]:
    """Import student-linked DOP rows from the selected workbook/JSON/HTTPS adapter."""
    from .main import read_sheet

    rows = read_sheet("Supplements")
    if not isinstance(rows, list):
        raise HTTPException(status_code=502, detail="Supplements source did not return a row list")
    imported = 0
    skipped = 0
    source_name = __import__("os").getenv("NAVIGATOR_DATA_SOURCE", "yandex").strip().lower()
    with core._db() as db:
        for raw in rows:
            if not isinstance(raw, dict):
                skipped += 1
                continue
            row = _normalized_row(raw)
            student_ref = _field(row, "student_id", "student_login", "student_username", "student_account", "student_name", "student", "login", "ученик_id", "логин_ученика", "ученик", "фио_ученика", "ученик_фио")
            title = _field(row, "title", "name", "supplement", "program", "program_name", "discipline", "subject", "название", "название_программы", "направление", "доп", "кружок")
            if not student_ref or not title:
                skipped += 1
                continue
            student = db.execute(
                "SELECT u.id FROM users u LEFT JOIN sso_identities s ON s.user_id=u.id "
                "WHERE u.role='student' AND u.active=1 AND "
                "(u.id=? OR u.username=? COLLATE NOCASE OR s.subject=?) LIMIT 1",
                (student_ref, student_ref, student_ref),
            ).fetchone()
            if not student:
                # Exact display-name matching is permitted only if unambiguous.
                candidates = db.execute(
                    "SELECT id FROM users WHERE role='student' AND active=1 AND display_name=? COLLATE NOCASE LIMIT 2",
                    (student_ref,),
                ).fetchall()
                if len(candidates) == 1:
                    student = candidates[0]
            if not student:
                skipped += 1
                continue
            weekday_raw = _field(row, "weekday", "day", "week_day", "день", "день_недели")
            weekday = _weekday(weekday_raw) if weekday_raw else None
            time_value = _field(row, "time", "start", "start_time", "время", "начало")
            teacher = _field(row, "teacher", "mentor", "coach", "преподаватель", "педагог")
            room = _field(row, "room", "cabinet", "location", "кабинет", "место")
            status = _field(row, "status", "state", "статус") or "active"
            if status.strip().lower() in {"active", "активно", "активен", "действует", "enabled", "true", "1"}:
                status = "active"
            elif status.strip().lower() in {"inactive", "неактивно", "отменено", "отменён", "disabled", "false", "0"}:
                status = "inactive"
            external_id = _field(row, "id", "supplement_id", "dop_id", "ид")
            stable_payload = json.dumps(
                [student["id"], external_id or "", title, weekday, time_value, teacher, room],
                ensure_ascii=False, separators=(",", ":")
            )
            source_key = "workbook:" + student["id"] + ":" + (("id:" + external_id) if external_id else hashlib.sha256(stable_payload.encode()).hexdigest())
            existing = db.execute(
                "SELECT id,title,weekday,time,teacher,room,status FROM student_supplements WHERE source_key=?",
                (source_key,)
            ).fetchone()
            if existing and (
                existing["title"] != title or existing["weekday"] != weekday or
                str(existing["time"] or "") != time_value or str(existing["teacher"] or "") != teacher or
                str(existing["room"] or "") != room or str(existing["status"] or "") != status
            ):
                _cancel_pending_dop_reminders(db, existing["id"])
            db.execute(
                "INSERT INTO student_supplements(id,student_id,title,weekday,time,teacher,room,status,updated_at,source_key) "
                "VALUES(?,?,?,?,?,?,?,?,?,?) ON CONFLICT(source_key) WHERE source_key IS NOT NULL DO UPDATE SET "
                "student_id=excluded.student_id,title=excluded.title,weekday=excluded.weekday,time=excluded.time,"
                "teacher=excluded.teacher,room=excluded.room,status=excluded.status,updated_at=excluded.updated_at",
                ("src_" + hashlib.sha256(source_key.encode()).hexdigest()[:24], student["id"], title, weekday,
                 time_value, teacher, room, status, _now(), source_key)
            )
            imported += 1
        db.execute(
            "INSERT INTO school_sync_runs(source,imported,skipped,created_at,result_json) VALUES(?,?,?,?,?)",
            (source_name, imported, skipped, _now(), json.dumps({"sheet": "Supplements"}, ensure_ascii=False))
        )
    core._audit(actor["id"], "school_data.supplements_synced", None,
                {"source": source_name, "imported": imported, "skipped": skipped})
    return {"status": "completed", "source": source_name, "rows_seen": len(rows),
            "imported_or_updated": imported, "skipped": skipped,
            "note": "Only rows mapped to an active student account are imported. Unmatched rows are skipped safely."}


@router.get("/management/sync/status")
def sync_status(actor: dict[str, Any] = Depends(require_permission("dop.read_all"))) -> dict[str, Any]:
    with core._db() as db:
        row = db.execute("SELECT source,imported,skipped,created_at,result_json FROM school_sync_runs ORDER BY id DESC LIMIT 1").fetchone()
    return {"last_run": dict(row) if row else None,
            "configured_source": __import__("os").getenv("NAVIGATOR_DATA_SOURCE", "yandex").strip().lower()}


@router.get("/announcements/workbook")
def list_workbook_announcements(actor: dict[str, Any] = Depends(core.current_user)) -> dict[str, Any]:
    from .main import _visible_announcements
    return {"data": _visible_announcements(actor.get("class_id"), include_class_targeted=True)}


@router.get("/management/dashboard")
def management_dashboard(actor: dict[str, Any] = Depends(require_permission("dashboard.read"))) -> dict[str, Any]:
    position, scope_class = _require_position_actor(actor, "dashboard.read")
    with core._db() as db:
        counts = {
            "students": db.execute("SELECT COUNT(*) AS n FROM users WHERE role='student' AND active=1" +
                                   (" AND class_id=?" if position == "homeroom_teacher" else ""),
                                   (scope_class,) if position == "homeroom_teacher" else ()).fetchone()["n"],
            "staff": db.execute("SELECT COUNT(*) AS n FROM users WHERE role IN ('teacher','mentor','admin') AND active=1").fetchone()["n"],
            "active_dop_records": db.execute("SELECT COUNT(*) AS n FROM student_supplements WHERE status='active'").fetchone()["n"],
            "announcements": db.execute("SELECT COUNT(*) AS n FROM announcements WHERE expires_at IS NULL OR expires_at>?", (_now(),)).fetchone()["n"],
        }
    if position == "homeroom_teacher":
        counts["active_dop_records"] = None
    return {"position": position, "scope_class": scope_class, "counts": counts}


@router.get("/management/students")
def management_students(actor: dict[str, Any] = Depends(core.current_user)) -> dict[str, Any]:
    position, scope_class = _position(actor["id"])
    if actor["role"] == "admin":
        position = "administrator"
    if position in {"director", "deputy", "dop_coordinator", "mentor_coordinator", "librarian", "administrator"}:
        sql = "SELECT id,display_name,class_id,active FROM users WHERE role='student' AND active=1 ORDER BY class_id,display_name"
        params: tuple[Any, ...] = ()
    elif position == "homeroom_teacher":
        sql = "SELECT id,display_name,class_id,active FROM users WHERE role='student' AND active=1 AND class_id=? ORDER BY display_name"
        params = (scope_class,)
    elif actor["role"] == "teacher":
        return core.list_students(actor)
    elif actor["role"] == "mentor":
        return core.list_students(actor)
    else:
        raise HTTPException(status_code=403, detail="Student directory is not available for this account")
    with core._db() as db:
        rows = db.execute(sql, params).fetchall()
    return {"data": [dict(row) for row in rows], "scope": scope_class or "school"}


@router.get("/management/students/{student_id}/supplements")
def management_student_supplements(student_id: str, actor: dict[str, Any] = Depends(core.current_user)) -> dict[str, Any]:
    position, scope_class = _position(actor["id"])
    if actor["role"] == "admin":
        position = "administrator"
    if position not in {"director", "deputy", "dop_coordinator", "administrator"}:
        if position == "homeroom_teacher":
            with core._db() as db:
                student = db.execute("SELECT class_id FROM users WHERE id=? AND role='student' AND active=1", (student_id,)).fetchone()
            if not student or student["class_id"] != scope_class:
                raise HTTPException(status_code=404, detail="Student not found")
        elif actor["role"] in {"mentor", "teacher"}:
            return core.get_student(student_id, actor)
        else:
            raise HTTPException(status_code=403, detail="DOP records are outside this account's scope")
    with core._db() as db:
        rows = db.execute(
            "SELECT id,title,weekday,time,teacher,room,status,updated_at FROM student_supplements "
            "WHERE student_id=? ORDER BY weekday,time", (student_id,)
        ).fetchall()
        student = db.execute("SELECT id,display_name,class_id FROM users WHERE id=? AND role='student' AND active=1", (student_id,)).fetchone()
    if not student:
        raise HTTPException(status_code=404, detail="Student not found")
    return {"student": dict(student), "data": [dict(row) for row in rows]}


def _cancel_pending_dop_reminders(db, supplement_id: str) -> None:
    try:
        rows = db.execute("SELECT notification_id FROM dop_reminder_occurrences WHERE supplement_id=?", (supplement_id,)).fetchall()
        for row in rows:
            db.execute(
                "UPDATE notifications SET delivery_status='cancelled',push_status='cancelled' "
                "WHERE id=? AND delivery_status IN ('queued','scheduled','retry')",
                (row["notification_id"],)
            )
        db.execute("DELETE FROM dop_reminder_occurrences WHERE supplement_id=?", (supplement_id,))
    except Exception:
        # Notification tables may not yet exist during a schema upgrade.
        return


@router.patch("/management/supplements/{supplement_id}")
def update_supplement(supplement_id: str, body: core.SupplementBody,
                      actor: dict[str, Any] = Depends(require_permission("dop.manage"))) -> dict[str, Any]:
    with core._db() as db:
        row = db.execute("SELECT student_id FROM student_supplements WHERE id=?", (supplement_id,)).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="DOP record not found")
        _cancel_pending_dop_reminders(db, supplement_id)
        db.execute(
            "UPDATE student_supplements SET title=?,weekday=?,time=?,teacher=?,room=?,status=?,updated_at=? WHERE id=?",
            (body.title, body.weekday, body.time, body.teacher, body.room, body.status, _now(), supplement_id)
        )
    core._audit(actor["id"], "student.supplement_updated", row["student_id"], {"supplement_id": supplement_id})
    return {"id": supplement_id, "student_id": row["student_id"], **body.model_dump(), "updated_at": _now()}


@router.delete("/management/supplements/{supplement_id}")
def delete_supplement(supplement_id: str,
                      actor: dict[str, Any] = Depends(require_permission("dop.manage"))) -> dict[str, str]:
    with core._db() as db:
        row = db.execute("SELECT student_id FROM student_supplements WHERE id=?", (supplement_id,)).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="DOP record not found")
        _cancel_pending_dop_reminders(db, supplement_id)
        db.execute("DELETE FROM student_supplements WHERE id=?", (supplement_id,))
    core._audit(actor["id"], "student.supplement_deleted", row["student_id"], {"supplement_id": supplement_id})
    return {"status": "deleted"}


@router.post("/management/students/{student_id}/supplements", status_code=201)
def management_add_supplement(student_id: str, body: core.SupplementBody,
                              actor: dict[str, Any] = Depends(core.current_user)) -> dict[str, Any]:
    position, _ = _position(actor["id"])
    if actor["role"] != "admin" and (position not in {"director", "deputy", "dop_coordinator"} or not _has(actor, "dop.manage")):
        raise HTTPException(status_code=403, detail="DOP management permission required")
    result = core.add_student_supplement(student_id, body, actor)
    return result


@router.post("/admin/assignments", status_code=201)
def assign_student(body: AssignmentBody, actor: dict[str, Any] = Depends(core.current_user)) -> dict[str, Any]:
    if actor["role"] != "admin" and not _has(actor, "assignments.manage"):
        raise HTTPException(status_code=403, detail="Assignment management permission required")
    if body.assignment_type not in {"mentor", "teacher"}:
        raise HTTPException(status_code=422, detail="assignment_type must be mentor or teacher")
    with core._db() as db:
        student = db.execute("SELECT role FROM users WHERE id=? AND active=1", (body.student_id,)).fetchone()
        staff = db.execute("SELECT role FROM users WHERE id=? AND active=1", (body.staff_id,)).fetchone()
        if not student or student["role"] != "student" or not staff or staff["role"] != body.assignment_type:
            raise HTTPException(status_code=422, detail="Student/staff roles do not match")
        if body.assignment_type == "mentor":
            db.execute("INSERT OR IGNORE INTO student_links(student_id,staff_id,link_type,subject,created_at) VALUES(?,?,?,?,?)",
                       (body.student_id, body.staff_id, "mentor", "", _now()))
        else:
            if not body.subject.strip():
                raise HTTPException(status_code=422, detail="Subject is required")
            db.execute("INSERT OR IGNORE INTO teacher_subject_assignments(student_id,staff_id,subject,created_at) VALUES(?,?,?,?)",
                       (body.student_id, body.staff_id, body.subject.strip(), _now()))
    core._audit(actor["id"], "student.assignment_created", body.student_id,
                {"staff_id": body.staff_id, "assignment_type": body.assignment_type, "subject": body.subject.strip()})
    return {"status": "assigned", **body.model_dump()}


@router.delete("/admin/assignments")
def unassign_student(body: AssignmentBody, actor: dict[str, Any] = Depends(core.current_user)) -> dict[str, str]:
    if actor["role"] != "admin" and not _has(actor, "assignments.manage"):
        raise HTTPException(status_code=403, detail="Assignment management permission required")
    with core._db() as db:
        if body.assignment_type == "mentor":
            cur = db.execute("DELETE FROM student_links WHERE student_id=? AND staff_id=? AND link_type='mentor'",
                             (body.student_id, body.staff_id))
        elif body.assignment_type == "teacher":
            cur = db.execute("DELETE FROM teacher_subject_assignments WHERE student_id=? AND staff_id=? AND subject=?",
                             (body.student_id, body.staff_id, body.subject.strip()))
        else:
            raise HTTPException(status_code=422, detail="Unknown assignment type")
    if not cur.rowcount:
        raise HTTPException(status_code=404, detail="Assignment not found")
    core._audit(actor["id"], "student.assignment_removed", body.student_id,
                {"staff_id": body.staff_id, "assignment_type": body.assignment_type, "subject": body.subject.strip()})
    return {"status": "removed"}
