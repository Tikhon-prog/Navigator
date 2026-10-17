"""Targeted and personal notification API, isolated from the legacy broadcast table."""
from __future__ import annotations

import asyncio
import os
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
          created_at TEXT NOT NULL, scheduled_at TEXT, expires_at TEXT,
          delivery_status TEXT NOT NULL DEFAULT 'queued', push_status TEXT NOT NULL DEFAULT 'pending',
          delivered_count INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX IF NOT EXISTS idx_notifications_created ON notifications(created_at);
        """)
        columns = {row["name"] for row in db.execute("PRAGMA table_info(notifications)").fetchall()}
        if "delivery_status" not in columns:
            db.execute("ALTER TABLE notifications ADD COLUMN delivery_status TEXT NOT NULL DEFAULT 'queued'")
        if "push_status" not in columns:
            db.execute("ALTER TABLE notifications ADD COLUMN push_status TEXT NOT NULL DEFAULT 'pending'")
        if "delivered_count" not in columns:
            db.execute("ALTER TABLE notifications ADD COLUMN delivered_count INTEGER NOT NULL DEFAULT 0")


@router.on_event("startup")
async def init_notifications() -> None:
    _init()
    if os.getenv("NAVIGATOR_NOTIFICATION_WORKER_ENABLED", "true").strip().lower() in {"1", "true", "yes", "on"}:
        global _worker_task
        if _worker_task is None or _worker_task.done():
            _worker_task = asyncio.create_task(_worker_loop())


_worker_task: asyncio.Task | None = None


async def _worker_loop() -> None:
    # One process is recommended. Database claim status also prevents two workers
    # from sending the same notification concurrently.
    while True:
        try:
            await asyncio.to_thread(_dispatch_due_notifications)
        except Exception:
            # The loop must survive a transient database/provider error.
            pass
        await asyncio.sleep(max(3, int(os.getenv("NAVIGATOR_NOTIFICATION_POLL_SECONDS", "10"))))


def _recipient_tokens(db, row) -> list[str]:
    target_type, target_id = row["target_type"], row["target_id"]
    if target_type == "all":
        result = db.execute("SELECT fcm_token FROM devices WHERE active=1")
    elif target_type == "class":
        result = db.execute("SELECT d.fcm_token FROM devices d JOIN users u ON u.id=d.user_id WHERE d.active=1 AND u.class_id=? AND u.active=1", (target_id,))
    elif target_type == "user":
        result = db.execute("SELECT d.fcm_token FROM devices d JOIN users u ON u.id=d.user_id WHERE d.active=1 AND u.id=? AND u.active=1", (target_id,))
    else:
        result = db.execute("SELECT d.fcm_token FROM devices d JOIN notification_group_members m ON m.user_id=d.user_id JOIN users u ON u.id=d.user_id WHERE d.active=1 AND u.active=1 AND m.group_id=?", (target_id,))
    return [item["fcm_token"] for item in result.fetchall()]


def _dispatch_due_notifications() -> int:
    now = _now()
    with core._db() as db:
        due = db.execute(
            "SELECT id FROM notifications WHERE delivery_status IN ('queued','scheduled') "
            "AND (scheduled_at IS NULL OR scheduled_at<=?) AND (expires_at IS NULL OR expires_at>?) "
            "ORDER BY COALESCE(scheduled_at,created_at),created_at LIMIT 50", (now, now)
        ).fetchall()
    sent_jobs = 0
    for item in due:
        notification_id = item["id"]
        with core._db() as db:
            claimed = db.execute(
                "UPDATE notifications SET delivery_status='processing' WHERE id=? AND delivery_status IN ('queued','scheduled')",
                (notification_id,)
            )
            if claimed.rowcount != 1:
                continue
            row = db.execute("SELECT * FROM notifications WHERE id=?", (notification_id,)).fetchone()
            tokens = _recipient_tokens(db, row)
        push_status, sent_count = core._send_push(
            tokens, row["title"], row["body"],
            {"notification_id": notification_id, "kind": row["kind"], "severity": "emergency" if row["kind"] == "emergency" else "info"}
        )
        status = "sent" if push_status == "sent" else "partial" if push_status == "partial" else "failed"
        with core._db() as db:
            db.execute(
                "UPDATE notifications SET delivery_status=?,push_status=?,delivered_count=? WHERE id=?",
                (status, push_status, sent_count, notification_id)
            )
        core._audit(row["created_by"], "notification.delivery_finished", notification_id,
                    {"delivery_status": status, "push_status": push_status, "delivered_count": sent_count})
        sent_jobs += 1
    return sent_jobs


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
                       actor: dict[str, Any] = Depends(core.current_user)) -> dict[str, Any]:
    from . import rbac_api
    position, scope_class = rbac_api._position(actor["id"])
    is_school_leadership = actor["role"] == "admin" or position in {"director", "deputy"}
    can_manage_dop = actor["role"] == "admin" or position in {"director", "deputy", "dop_coordinator"}
    can_class_broadcast = is_school_leadership or position == "homeroom_teacher"
    if actor["role"] not in {"admin", "teacher", "mentor"} and not position:
        raise HTTPException(status_code=403, detail="Notification publishing is not available for this account")
    kinds = {"global", "targeted", "personal", "dop_reminder", "emergency"}
    targets = {"all", "class", "group", "user"}
    if body.kind not in kinds or body.target_type not in targets:
        raise HTTPException(status_code=422, detail="Unsupported notification kind or target_type")
    if body.kind == "global" and body.target_type != "all":
        raise HTTPException(status_code=422, detail="Global notifications must target all users")
    if body.kind in {"personal", "dop_reminder"} and body.target_type != "user":
        raise HTTPException(status_code=422, detail="Personal and DOP reminders must target one user")
    if body.kind == "emergency" and not is_school_leadership:
        raise HTTPException(status_code=403, detail="Only school leadership may publish emergency notifications")
    if body.kind == "global" and not is_school_leadership:
        raise HTTPException(status_code=403, detail="Only school leadership may publish global notifications")
    if body.kind == "dop_reminder" and not can_manage_dop and actor["role"] not in {"student"}:
        raise HTTPException(status_code=403, detail="DOP reminder permission required")
    if actor["role"] == "teacher" and not is_school_leadership and body.target_type not in {"user", "class"}:
        raise HTTPException(status_code=403, detail="Teachers may notify only assigned students")
    if actor["role"] == "teacher" and not is_school_leadership and body.target_type == "class" and position != "homeroom_teacher":
        raise HTTPException(status_code=403, detail="Class broadcast requires homeroom-teacher assignment")
    if body.target_type == "all" and not is_school_leadership:
        raise HTTPException(status_code=403, detail="Global target requires school leadership")
    if body.target_type == "class" and not can_class_broadcast:
        raise HTTPException(status_code=403, detail="Class-targeted publishing permission required")
    if body.kind == "emergency" and body.scheduled_at:
        raise HTTPException(status_code=422, detail="Emergency notifications cannot be scheduled")
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
            if actor["role"] == "teacher" and not is_school_leadership:
                linked = db.execute("SELECT 1 FROM teacher_subject_assignments WHERE student_id=? AND staff_id=?",
                                    (body.target_id, actor["id"])).fetchone()
                if target["role"] != "student" or not linked:
                    raise HTTPException(status_code=403, detail="Student is not assigned to this teacher")
        elif body.target_type == "class":
            if position == "homeroom_teacher" and body.target_id != scope_class:
                raise HTTPException(status_code=403, detail="Homeroom teacher may publish only to their assigned class")
            target = db.execute("SELECT 1 FROM users WHERE role='student' AND class_id=? AND active=1 LIMIT 1", (body.target_id,)).fetchone()
            if not target:
                raise HTTPException(status_code=404, detail="Target class not found")
        elif body.target_type == "group":
            target = db.execute("SELECT id FROM notification_groups WHERE id=?", (body.target_id,)).fetchone()
            if not target:
                raise HTTPException(status_code=404, detail="Target group not found")
        notification_id = secrets.token_urlsafe(12)
        created_at = _now()
        delivery_status = "scheduled" if body.scheduled_at and body.scheduled_at > created_at else "queued"
        db.execute("INSERT INTO notifications(id,title,body,kind,target_type,target_id,created_by,created_at,scheduled_at,expires_at,delivery_status) VALUES(?,?,?,?,?,?,?,?,?,?,?)",
                   (notification_id, body.title, body.body, body.kind, body.target_type, body.target_id, actor["id"], created_at, body.scheduled_at, body.expires_at, delivery_status))
    core._audit(actor["id"], "notification.created", notification_id,
                {"kind": body.kind, "target_type": body.target_type, "target_id": body.target_id})
    return {"id": notification_id, "title": body.title, "body": body.body, "kind": body.kind,
            "target_type": body.target_type, "target_id": body.target_id, "created_at": created_at,
            "scheduled_at": body.scheduled_at, "delivery_status": delivery_status, "push_status": "pending"}


@router.get("/notifications")
def list_notifications(actor: dict[str, Any] = Depends(core.current_user)) -> dict[str, Any]:
    now = _now()
    with core._db() as db:
        rows = db.execute("SELECT * FROM notifications WHERE (scheduled_at IS NULL OR scheduled_at<=?) AND (expires_at IS NULL OR expires_at>?) AND delivery_status!='processing' ORDER BY created_at DESC LIMIT 200", (now, now)).fetchall()
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
