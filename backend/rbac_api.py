"""Role/position extensions for school leadership and operational staff.

Base login roles stay backward-compatible; a separate position and explicit scope
grant additional school duties without making every deputy/teacher an administrator.
"""
from __future__ import annotations

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
        """)


@router.on_event("startup")
def init_roles() -> None:
    _init()


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


@router.get("/auth/permissions")
def my_permissions(actor: dict[str, Any] = Depends(core.current_user)) -> dict[str, Any]:
    position, scope_class = _position(actor["id"])
    grants = sorted(PERMISSIONS.get(position or "", set()))
    if actor.get("role") == "admin":
        grants = ["*"]
    return {"user": actor, "position": position, "scope_class": scope_class, "permissions": grants}


@router.get("/admin/users")
def list_users(actor: dict[str, Any] = Depends(require_permission("staff.read"))) -> dict[str, Any]:
    with core._db() as db:
        rows = db.execute(
            "SELECT u.id,u.username,u.role,u.display_name,u.class_id,u.active,u.created_at,"
            "p.position,p.scope_class FROM users u LEFT JOIN staff_positions p ON p.user_id=u.id "
            "ORDER BY u.role,u.display_name LIMIT 2000"
        ).fetchall()
    return {"data": [dict(row) for row in rows]}


@router.patch("/admin/users/{user_id}")
def patch_user(user_id: str, body: UserPatch,
               actor: dict[str, Any] = Depends(require_permission("staff.manage"))) -> dict[str, Any]:
    changes = body.model_dump(exclude_unset=True)
    if not changes:
        raise HTTPException(status_code=422, detail="No fields to update")
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
    with core._db() as db:
        exists = db.execute("SELECT id FROM users WHERE id=?", (user_id,)).fetchone()
        if not exists:
            raise HTTPException(status_code=404, detail="Account not found")
        db.execute(f"UPDATE users SET {','.join(fields)} WHERE id=?", (*values, user_id))
        row = db.execute(
            "SELECT u.id,u.username,u.role,u.display_name,u.class_id,u.active,p.position,p.scope_class "
            "FROM users u LEFT JOIN staff_positions p ON p.user_id=u.id WHERE u.id=?", (user_id,)
        ).fetchone()
    core._audit(actor["id"], "user.updated", user_id, {"fields": sorted(changes)})
    return {"user": dict(row)}


@router.put("/admin/staff-positions")
def assign_position(body: PositionBody,
                    actor: dict[str, Any] = Depends(core.require_roles("admin"))) -> dict[str, Any]:
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
        db.execute(
            "INSERT INTO staff_positions(user_id,position,scope_class,assigned_by,updated_at) VALUES(?,?,?,?,?) "
            "ON CONFLICT(user_id) DO UPDATE SET position=excluded.position,scope_class=excluded.scope_class,"
            "assigned_by=excluded.assigned_by,updated_at=excluded.updated_at",
            (user["id"], body.position, body.scope_class, actor["id"], _now()),
        )
    core._audit(actor["id"], "staff.position_assigned", user["id"], {"position": body.position, "scope_class": body.scope_class})
    return {"status": "assigned", "user_id": user["id"], "position": body.position, "scope_class": body.scope_class}


@router.delete("/admin/staff-positions/{user_id}")
def remove_position(user_id: str, actor: dict[str, Any] = Depends(core.require_roles("admin"))) -> dict[str, str]:
    with core._db() as db:
        cur = db.execute("DELETE FROM staff_positions WHERE user_id=?", (user_id,))
    if not cur.rowcount:
        raise HTTPException(status_code=404, detail="Position assignment not found")
    core._audit(actor["id"], "staff.position_removed", user_id)
    return {"status": "removed"}


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
