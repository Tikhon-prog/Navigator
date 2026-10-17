"""Targeted and personal notification API, isolated from the legacy broadcast table."""
from __future__ import annotations

import secrets
from datetime import datetime, timezone
from typing import Any

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from . import school_api as core

router = APIRouter(prefix="/api/v2", tags=["targeted notifications"])


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _init() -> None:
    with core._db() as db:
        db.executescript("""
        CREATE TABLE IF NOT EXISTS notification_groups (
          id TEXT PRIMARY KEY, name TEXT NOT NULL UNIQUE, created_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS notification_group_members (
          group_id TEXT NOT NULL REFERENCES notification_groups(id) ON DELETE CASCADE,
          user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          PRIMARY KEY(group_id,user_id)
        );
        CREATE TABLE IF NOT EXISTS notifications (
          id TEXT PRIMARY KEY, title TEXT NOT NULL, body TEXT NOT NULL,
          kind TEXT NOT NULL CHECK(kind IN ('global','targeted','personal','dop_reminder','emergency')),
          target_type TEXT NOT NULL CHECK(target_type IN ('all','class','group','user')),
          target_id TEXT, created_by TEXT NOT NULL REFERENCES users(id),
          created_at TEXT NOT NULL, scheduled_at TEXT, expires_at TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_notifications_created ON notifications(created_at);
        """)


@router.on_event("startup")
def init_notifications() -> None:
    _init()


class GroupBody(BaseModel):
    name: str = Field(min_length=1, max_length=120)


class GroupMemberBody(BaseModel):
    user_id: str = Field(min_length=1, max_length=128)


class NotificationBody(BaseModel):
    title: str = Field(min_length=1, max_length=180)
    body: str = Field(min_length=1, max_length=4000)
    kind: str = "global"
    target_type: str = "all"
    target_id: str | None = Field(default=None, max_length=128)
    scheduled_at: str | None = Field(default=None, max_length=50)
    expires_at: str | None = Field(default=None, max_length=50)


@router.post("/admin/notification-groups", status_code=201)
def create_group(body: GroupBody, actor: dict[str, Any] = Depends(core.require_roles("admin"))) -> dict[str, str]:
    group_id = secrets.token_urlsafe(12)
    try:
        with core._db() as db:
            db.execute("INSERT INTO notification_groups(id,name,created_at) VALUES(?,?,?)", (group_id, body.name, _now()))
    except Exception:
        raise HTTPException(status_code=409, detail="Group name already exists")
    core._audit(actor["id"], "notification_group.created", group_id)
    return {"id": group_id, "name": body.name}


@router.post("/admin/notification-groups/{group_id}/members", status_code=201)
def add_group_member(group_id: str, body: GroupMemberBody,
                     actor: dict[str, Any] = Depends(core.require_roles("admin"))) -> dict[str, str]:
    with core._db() as db:
        group = db.execute("SELECT id FROM notification_groups WHERE id=?", (group_id,)).fetchone()
        user = db.execute("SELECT id FROM users WHERE id=? AND active=1", (body.user_id,)).fetchone()
        if not group or not user:
            raise HTTPException(status_code=404, detail="Group or active user not found")
        db.execute("INSERT OR IGNORE INTO notification_group_members(group_id,user_id) VALUES(?,?)", (group_id, body.user_id))
    core._audit(actor["id"], "notification_group.member_added", group_id, {"user_id": body.user_id})
    return {"status": "added", "group_id": group_id, "user_id": body.user_id}


@router.post("/admin/notifications", status_code=201)
def create_notification(body: NotificationBody,
                       actor: dict[str, Any] = Depends(core.require_roles("admin", "teacher"))) -> dict[str, Any]:
    kinds = {"global", "targeted", "personal", "dop_reminder", "emergency"}
    targets = {"all", "class", "group", "user"}
    if body.kind not in kinds or body.target_type not in targets:
        raise HTTPException(status_code=422, detail="Unsupported notification kind or target_type")
    if body.kind == "global" and body.target_type != "all":
        raise HTTPException(status_code=422, detail="Global notifications must target all users")
    if body.kind in {"personal", "dop_reminder"} and body.target_type != "user":
        raise HTTPException(status_code=422, detail="Personal and DOP reminders must target one user")
    if body.kind == "emergency" and actor["role"] != "admin":
        raise HTTPException(status_code=403, detail="Only administrators may publish emergency notifications")
    if actor["role"] == "teacher" and body.target_type != "user":
        raise HTTPException(status_code=403, detail="Teachers may notify only explicitly assigned students")
    if body.target_type != "all" and not body.target_id:
        raise HTTPException(status_code=422, detail="target_id is required for this target_type")
    for value in (body.scheduled_at, body.expires_at):
        if value:
            try:
                datetime.fromisoformat(value.replace("Z", "+00:00"))
            except ValueError:
                raise HTTPException(status_code=422, detail="Dates must be ISO-8601 timestamps")
    with core._db() as db:
        if body.target_type == "user":
            target = db.execute("SELECT id,role FROM users WHERE id=? AND active=1", (body.target_id,)).fetchone()
            if not target:
                raise HTTPException(status_code=404, detail="Active target user not found")
            if actor["role"] == "teacher":
                linked = db.execute("SELECT 1 FROM student_links WHERE student_id=? AND staff_id=? AND link_type='teacher'",
                                    (body.target_id, actor["id"])).fetchone()
                if target["role"] != "student" or not linked:
                    raise HTTPException(status_code=403, detail="Student is not assigned to this teacher")
        elif body.target_type == "class":
            target = db.execute("SELECT 1 FROM users WHERE role='student' AND class_id=? AND active=1 LIMIT 1", (body.target_id,)).fetchone()
            if not target:
                raise HTTPException(status_code=404, detail="Target class not found")
        elif body.target_type == "group":
            target = db.execute("SELECT id FROM notification_groups WHERE id=?", (body.target_id,)).fetchone()
            if not target:
                raise HTTPException(status_code=404, detail="Target group not found")
        notification_id = secrets.token_urlsafe(12)
        created_at = _now()
        db.execute("INSERT INTO notifications(id,title,body,kind,target_type,target_id,created_by,created_at,scheduled_at,expires_at) VALUES(?,?,?,?,?,?,?,?,?,?)",
                   (notification_id, body.title, body.body, body.kind, body.target_type, body.target_id, actor["id"], created_at, body.scheduled_at, body.expires_at))
    core._audit(actor["id"], "notification.created", notification_id,
                {"kind": body.kind, "target_type": body.target_type, "target_id": body.target_id})
    # Scheduled entries are stored for a scheduler worker; this endpoint intentionally does not pretend they were delivered.
    return {"id": notification_id, "title": body.title, "body": body.body, "kind": body.kind,
            "target_type": body.target_type, "target_id": body.target_id, "created_at": created_at,
            "scheduled_at": body.scheduled_at, "delivery_status": "scheduled" if body.scheduled_at else "queued_not_sent"}


@router.get("/notifications")
def list_notifications(actor: dict[str, Any] = Depends(core.current_user)) -> dict[str, Any]:
    now = _now()
    with core._db() as db:
        rows = db.execute("SELECT * FROM notifications WHERE (scheduled_at IS NULL OR scheduled_at<=?) AND (expires_at IS NULL OR expires_at>?) ORDER BY created_at DESC LIMIT 200", (now, now)).fetchall()
        visible = []
        for row in rows:
            if row["target_type"] == "all":
                visible.append(dict(row))
            elif row["target_type"] == "user" and row["target_id"] == actor["id"]:
                visible.append(dict(row))
            elif row["target_type"] == "class" and actor.get("class_id") and row["target_id"] == actor["class_id"]:
                visible.append(dict(row))
            elif row["target_type"] == "group":
                member = db.execute("SELECT 1 FROM notification_group_members WHERE group_id=? AND user_id=?", (row["target_id"], actor["id"])).fetchone()
                if member:
                    visible.append(dict(row))
    return {"data": visible}
