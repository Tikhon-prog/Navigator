"""Targeted and personal notification API, isolated from the legacy broadcast table."""
from __future__ import annotations

import asyncio
import os
import re
import secrets
from datetime import datetime, time as datetime_time, timedelta, timezone
from zoneinfo import ZoneInfo
from typing import Any

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from . import school_api as core

router = APIRouter(prefix="/api/v2", tags=["targeted notifications"])


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _normalize_timestamp(value: str | None) -> str | None:
    if not value:
        return None
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc).isoformat()


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
          delivered_count INTEGER NOT NULL DEFAULT 0, delivery_attempts INTEGER NOT NULL DEFAULT 0,
          next_attempt_at TEXT, last_error_code TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_notifications_created ON notifications(created_at);
        CREATE TABLE IF NOT EXISTS notification_preferences (
          user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
          dop_reminders_enabled INTEGER NOT NULL DEFAULT 0,
          updated_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS dop_reminder_occurrences (
          id TEXT PRIMARY KEY, supplement_id TEXT NOT NULL REFERENCES student_supplements(id) ON DELETE CASCADE,
          student_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          starts_at TEXT NOT NULL, notification_id TEXT NOT NULL UNIQUE REFERENCES notifications(id) ON DELETE CASCADE,
          UNIQUE(supplement_id,student_id,starts_at)
        );
        """)
        columns = {row["name"] for row in db.execute("PRAGMA table_info(notifications)").fetchall()}
        if "delivery_status" not in columns:
            db.execute("ALTER TABLE notifications ADD COLUMN delivery_status TEXT NOT NULL DEFAULT 'queued'")
        if "push_status" not in columns:
            db.execute("ALTER TABLE notifications ADD COLUMN push_status TEXT NOT NULL DEFAULT 'pending'")
        if "delivered_count" not in columns:
            db.execute("ALTER TABLE notifications ADD COLUMN delivered_count INTEGER NOT NULL DEFAULT 0")
        if "delivery_attempts" not in columns:
            db.execute("ALTER TABLE notifications ADD COLUMN delivery_attempts INTEGER NOT NULL DEFAULT 0")
        if "next_attempt_at" not in columns:
            db.execute("ALTER TABLE notifications ADD COLUMN next_attempt_at TEXT")
        if "last_error_code" not in columns:
            db.execute("ALTER TABLE notifications ADD COLUMN last_error_code TEXT")
        # Recover claimed jobs left behind by an abrupt container restart.
        db.execute("UPDATE notifications SET delivery_status='retry',next_attempt_at=? WHERE delivery_status='processing'",
                   (_now(),))


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
            await asyncio.to_thread(_enqueue_dop_reminders)
            await asyncio.to_thread(_dispatch_due_notifications)
        except Exception:
            # The loop must survive a transient database/provider error.
            pass
        try:
            poll_seconds = int(os.getenv("NAVIGATOR_NOTIFICATION_POLL_SECONDS", "10"))
        except ValueError:
            poll_seconds = 10
        await asyncio.sleep(max(3, min(300, poll_seconds)))


def _recipient_tokens(db, row) -> list[str]:
    target_type, target_id = row["target_type"], row["target_id"]
    if target_type == "all":
        result = db.execute(
            "SELECT d.fcm_token FROM devices d JOIN users u ON u.id=d.user_id "
            "WHERE d.active=1 AND u.active=1"
        )
    elif target_type == "class":
        rows = db.execute(
            "SELECT d.fcm_token,u.class_id FROM devices d JOIN users u ON u.id=d.user_id "
            "WHERE d.active=1 AND u.active=1 AND u.role='student'"
        ).fetchall()
        wanted_class = core.normalize_class_id(target_id)
        return [row["fcm_token"] for row in rows if core.normalize_class_id(row["class_id"]) == wanted_class]
    elif target_type == "user":
        result = db.execute("SELECT d.fcm_token FROM devices d JOIN users u ON u.id=d.user_id WHERE d.active=1 AND u.id=? AND u.active=1", (target_id,))
    else:
        result = db.execute("SELECT d.fcm_token FROM devices d JOIN notification_group_members m ON m.user_id=d.user_id JOIN users u ON u.id=d.user_id WHERE d.active=1 AND u.active=1 AND m.group_id=?", (target_id,))
    return [item["fcm_token"] for item in result.fetchall()]


class NotificationPreferencesBody(BaseModel):
    dop_reminders_enabled: bool = False


@router.get("/notifications/preferences")
def get_notification_preferences(actor: dict[str, Any] = Depends(core.current_user)) -> dict[str, Any]:
    with core._db() as db:
        row = db.execute("SELECT dop_reminders_enabled,updated_at FROM notification_preferences WHERE user_id=?", (actor["id"],)).fetchone()
    return {"dop_reminders_enabled": bool(row["dop_reminders_enabled"]) if row else False,
            "updated_at": row["updated_at"] if row else None}


@router.put("/notifications/preferences")
def set_notification_preferences(body: NotificationPreferencesBody,
                                 actor: dict[str, Any] = Depends(core.current_user)) -> dict[str, Any]:
    with core._db() as db:
        db.execute(
            "INSERT INTO notification_preferences(user_id,dop_reminders_enabled,updated_at) VALUES(?,?,?) "
            "ON CONFLICT(user_id) DO UPDATE SET dop_reminders_enabled=excluded.dop_reminders_enabled,updated_at=excluded.updated_at",
            (actor["id"], int(body.dop_reminders_enabled), _now()),
        )
    core._audit(actor["id"], "notification.preferences_updated", actor["id"],
                {"dop_reminders_enabled": body.dop_reminders_enabled})
    return {"dop_reminders_enabled": body.dop_reminders_enabled}


def _enqueue_dop_reminders() -> int:
    """Create idempotent per-student push reminders 15 minutes before opted-in DOPs."""
    timezone_name = os.getenv("NAVIGATOR_SCHOOL_TIMEZONE", "Europe/Moscow").strip() or "Europe/Moscow"
    try:
        school_tz = ZoneInfo(timezone_name)
    except Exception:
        school_tz = ZoneInfo("UTC")
    now_local = datetime.now(school_tz)
    now_utc = now_local.astimezone(timezone.utc)
    horizon = now_utc + timedelta(days=8)
    inserted = 0
    with core._db() as db:
        records = db.execute(
            "SELECT s.id AS supplement_id,s.student_id,s.title,s.weekday,s.time,s.room "
            "FROM student_supplements s JOIN users u ON u.id=s.student_id AND u.active=1 "
            "JOIN notification_preferences p ON p.user_id=s.student_id AND p.dop_reminders_enabled=1 "
            "WHERE s.status='active' AND s.weekday BETWEEN 1 AND 7"
        ).fetchall()
        for record in records:
            match = re.search(r"(\d{1,2}):(\d{2})", str(record["time"] or ""))
            if not match:
                continue
            hour, minute = int(match.group(1)), int(match.group(2))
            if hour > 23 or minute > 59:
                continue
            for offset in range(0, 8):
                day = (now_local.date() + timedelta(days=offset))
                if day.isoweekday() != record["weekday"]:
                    continue
                starts_local = datetime.combine(day, datetime_time(hour, minute), tzinfo=school_tz)
                starts_utc = starts_local.astimezone(timezone.utc)
                remind_utc = starts_utc - timedelta(minutes=15)
                if remind_utc <= now_utc or remind_utc > horizon:
                    continue
                starts_iso = starts_utc.isoformat()
                exists = db.execute(
                    "SELECT 1 FROM dop_reminder_occurrences WHERE supplement_id=? AND student_id=? AND starts_at=?",
                    (record["supplement_id"], record["student_id"], starts_iso)
                ).fetchone()
                if exists:
                    continue
                notification_id = secrets.token_urlsafe(12)
                db.execute("SAVEPOINT dop_reminder_occurrence")
                try:
                    db.execute(
                        "INSERT INTO notifications(id,title,body,kind,target_type,target_id,created_by,created_at,scheduled_at,expires_at,delivery_status) "
                        "VALUES(?,?,?,?,?,?,?,?,?,?, 'scheduled')",
                        (notification_id, "Напоминание о ДОПе",
                         f"{record['title']} • начало в {hour:02d}:{minute:02d}" +
                         (f" • кабинет {record['room']}" if record["room"] else ""),
                         "dop_reminder", "user", record["student_id"], record["student_id"],
                         _now(), remind_utc.isoformat(), starts_iso)
                    )
                    db.execute(
                        "INSERT INTO dop_reminder_occurrences(id,supplement_id,student_id,starts_at,notification_id) VALUES(?,?,?,?,?)",
                        (secrets.token_urlsafe(12), record["supplement_id"], record["student_id"], starts_iso, notification_id)
                    )
                    db.execute("RELEASE SAVEPOINT dop_reminder_occurrence")
                    inserted += 1
                except Exception:
                    db.execute("ROLLBACK TO SAVEPOINT dop_reminder_occurrence")
                    db.execute("RELEASE SAVEPOINT dop_reminder_occurrence")
                    continue
    return inserted


def _dispatch_due_notifications() -> int:
    now = _now()
    with core._db() as db:
        db.execute(
            "UPDATE notifications SET delivery_status='expired',push_status='expired',next_attempt_at=NULL "
            "WHERE delivery_status IN ('queued','scheduled','retry') AND expires_at IS NOT NULL AND expires_at<=?",
            (now,)
        )
        due = db.execute(
            "SELECT id FROM notifications WHERE delivery_status IN ('queued','scheduled','retry') "
            "AND (next_attempt_at IS NULL OR next_attempt_at<=?) "
            "AND (scheduled_at IS NULL OR scheduled_at<=?) AND (expires_at IS NULL OR expires_at>?) "
            "ORDER BY COALESCE(next_attempt_at,scheduled_at,created_at),created_at LIMIT 50", (now, now, now)
        ).fetchall()
    sent_jobs = 0
    for item in due:
        notification_id = item["id"]
        with core._db() as db:
            claimed = db.execute(
                "UPDATE notifications SET delivery_status='processing',delivery_attempts=delivery_attempts+1,next_attempt_at=NULL "
                "WHERE id=? AND delivery_status IN ('queued','scheduled','retry') AND (next_attempt_at IS NULL OR next_attempt_at<=?)",
                (notification_id, now)
            )
            if claimed.rowcount != 1:
                continue
            row = db.execute("SELECT * FROM notifications WHERE id=?", (notification_id,)).fetchone()
            tokens = _recipient_tokens(db, row)
        push_status, sent_count = core._send_push(
            tokens, row["title"], row["body"],
            {"notification_id": notification_id, "kind": row["kind"], "severity": "emergency" if row["kind"] == "emergency" else "info"}
        )
        attempt_count = int(row["delivery_attempts"] or 1)
        # Missing credentials/packages and invalid registration tokens are
        # configuration or recipient failures, not transient network failures.
        # Retrying those on a timer only hides the problem and wastes work.
        # A partial send is also terminal to avoid duplicate pushes.
        retryable = push_status == "provider_error" and sent_count == 0 and attempt_count < 6
        if retryable:
            status = "retry"
            backoff_seconds = min(3600, 15 * (2 ** (attempt_count - 1)))
            next_attempt = (datetime.now(timezone.utc) + timedelta(seconds=backoff_seconds)).isoformat()
        else:
            status = "sent" if push_status == "sent" else "partial" if push_status == "partial" else "failed"
            next_attempt = None
        with core._db() as db:
            db.execute(
                "UPDATE notifications SET delivery_status=?,push_status=?,delivered_count=?,next_attempt_at=?,last_error_code=? WHERE id=?",
                (status, push_status, sent_count, next_attempt, None if push_status == "sent" else push_status, notification_id)
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


def _can_manage_groups(actor: dict[str, Any]) -> bool:
    if actor.get("role") == "admin":
        return True
    from . import rbac_api
    return rbac_api._has(actor, "assignments.manage")


def require_group_manager(actor: dict[str, Any] = Depends(core.current_user)) -> dict[str, Any]:
    if not _can_manage_groups(actor):
        raise HTTPException(status_code=403, detail="Notification-group management permission required")
    return actor


@router.get("/admin/notification-groups")
def list_groups(actor: dict[str, Any] = Depends(require_group_manager)) -> dict[str, Any]:
    with core._db() as db:
        rows = db.execute(
            "SELECT g.id,g.name,g.created_at,COUNT(m.user_id) AS member_count "
            "FROM notification_groups g LEFT JOIN notification_group_members m ON m.group_id=g.id "
            "GROUP BY g.id,g.name,g.created_at ORDER BY g.name"
        ).fetchall()
    return {"data": [dict(row) for row in rows]}


@router.get("/admin/notification-groups/{group_id}/members")
def list_group_members(group_id: str,
                       actor: dict[str, Any] = Depends(require_group_manager)) -> dict[str, Any]:
    with core._db() as db:
        group = db.execute("SELECT id,name FROM notification_groups WHERE id=?", (group_id,)).fetchone()
        if not group:
            raise HTTPException(status_code=404, detail="Notification group not found")
        rows = db.execute(
            "SELECT u.id,u.username,u.role,u.display_name,u.class_id FROM notification_group_members m "
            "JOIN users u ON u.id=m.user_id WHERE m.group_id=? AND u.active=1 ORDER BY u.display_name",
            (group_id,)
        ).fetchall()
    return {"group": dict(group), "data": [dict(row) for row in rows]}


@router.post("/admin/notification-groups", status_code=201)
def create_group(body: GroupBody, actor: dict[str, Any] = Depends(require_group_manager)) -> dict[str, str]:
    require_group_manager(actor)
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
                     actor: dict[str, Any] = Depends(require_group_manager)) -> dict[str, str]:
    from . import rbac_api
    actor_position, _ = (None, None) if actor["role"] == "admin" else rbac_api._position(actor["id"])
    school_leadership = actor["role"] == "admin" or actor_position in {"director", "deputy"}
    with core._db() as db:
        group = db.execute("SELECT id FROM notification_groups WHERE id=?", (group_id,)).fetchone()
        user = db.execute("SELECT id,role FROM users WHERE id=? AND active=1", (body.user_id,)).fetchone()
        if not group or not user:
            raise HTTPException(status_code=404, detail="Group or active user not found")
        # Non-leadership coordinators may build student delivery groups, but
        # cannot use that power to create a group broadcast to staff accounts.
        if not school_leadership and user["role"] != "student":
            raise HTTPException(status_code=403, detail="Only school leadership may add staff accounts to notification groups")
        db.execute("INSERT OR IGNORE INTO notification_group_members(group_id,user_id) VALUES(?,?)", (group_id, body.user_id))
    core._audit(actor["id"], "notification_group.member_added", group_id, {"user_id": body.user_id})
    return {"status": "added", "group_id": group_id, "user_id": body.user_id}


@router.delete("/admin/notification-groups/{group_id}/members/{user_id}")
def remove_group_member(group_id: str, user_id: str,
                        actor: dict[str, Any] = Depends(require_group_manager)) -> dict[str, str]:
    with core._db() as db:
        cur = db.execute(
            "DELETE FROM notification_group_members WHERE group_id=? AND user_id=?",
            (group_id, user_id)
        )
    if not cur.rowcount:
        raise HTTPException(status_code=404, detail="Group membership not found")
    core._audit(actor["id"], "notification_group.member_removed", group_id, {"user_id": user_id})
    return {"status": "removed", "group_id": group_id, "user_id": user_id}


@router.delete("/admin/notification-groups/{group_id}")
def delete_group(group_id: str,
                 actor: dict[str, Any] = Depends(require_group_manager)) -> dict[str, str]:
    with core._db() as db:
        cur = db.execute("DELETE FROM notification_groups WHERE id=?", (group_id,))
    if not cur.rowcount:
        raise HTTPException(status_code=404, detail="Notification group not found")
    core._audit(actor["id"], "notification_group.deleted", group_id)
    return {"status": "deleted", "group_id": group_id}


@router.post("/admin/notifications", status_code=201)
def create_notification(body: NotificationBody,
                       actor: dict[str, Any] = Depends(core.current_user)) -> dict[str, Any]:
    from . import rbac_api
    position, scope_class = (None, None) if actor["role"] == "admin" else rbac_api._position(actor["id"])
    is_school_leadership = actor["role"] == "admin" or position in {"director", "deputy"}
    can_manage_dop = actor["role"] == "admin" or position in {"director", "deputy", "dop_coordinator"}
    can_class_broadcast = is_school_leadership or position in {"homeroom_teacher", "dop_coordinator"}
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
    # Students opt in through /notifications/preferences; only authorized
    # staff can create/remediate reminder records. Otherwise a student could
    # target arbitrary accounts and manufacture personal notifications.
    if body.kind == "dop_reminder" and not can_manage_dop:
        raise HTTPException(status_code=403, detail="DOP reminder management permission required")
    if actor["role"] == "teacher" and not is_school_leadership and body.target_type not in {"user", "class"}:
        raise HTTPException(status_code=403, detail="Teachers may notify only assigned students")
    if actor["role"] == "teacher" and not is_school_leadership and body.target_type == "class" and position not in {"homeroom_teacher", "dop_coordinator"}:
        raise HTTPException(status_code=403, detail="Class broadcast requires an assigned school position")
    if body.target_type == "all" and not is_school_leadership:
        raise HTTPException(status_code=403, detail="Global target requires school leadership")
    if body.target_type == "group" and not is_school_leadership and not rbac_api._has(actor, "assignments.manage"):
        raise HTTPException(status_code=403, detail="Notification-group publishing permission required")
    if body.target_type == "class" and not can_class_broadcast:
        raise HTTPException(status_code=403, detail="Class-targeted publishing permission required")
    if body.kind == "emergency" and body.scheduled_at:
        raise HTTPException(status_code=422, detail="Emergency notifications cannot be scheduled")
    if body.target_type != "all" and not body.target_id:
        raise HTTPException(status_code=422, detail="target_id is required for this target_type")
    try:
        scheduled_at = _normalize_timestamp(body.scheduled_at)
        expires_at = _normalize_timestamp(body.expires_at)
    except ValueError:
        raise HTTPException(status_code=422, detail="Dates must be ISO-8601 timestamps")
    now_dt = datetime.now(timezone.utc)
    if expires_at and datetime.fromisoformat(expires_at) <= now_dt:
        raise HTTPException(status_code=422, detail="expires_at must be in the future")
    if scheduled_at and expires_at and datetime.fromisoformat(expires_at) <= datetime.fromisoformat(scheduled_at):
        raise HTTPException(status_code=422, detail="expires_at must be later than scheduled_at")
    with core._db() as db:
        if body.target_type == "user":
            target = db.execute("SELECT id,role FROM users WHERE id=? AND active=1", (body.target_id,)).fetchone()
            if not target:
                raise HTTPException(status_code=404, detail="Active target user not found")
            if body.kind == "dop_reminder":
                if target["role"] != "student":
                    raise HTTPException(status_code=422, detail="DOP reminders must target a student")
                has_active_dop = db.execute(
                    "SELECT 1 FROM student_supplements WHERE student_id=? AND status='active' LIMIT 1",
                    (body.target_id,)
                ).fetchone()
                if not has_active_dop:
                    raise HTTPException(status_code=422, detail="No active DOP record exists for this student")
            if not is_school_leadership and target["role"] != "student":
                raise HTTPException(status_code=403, detail="Staff without school-wide leadership may notify only student accounts")
            if actor["role"] == "teacher" and not is_school_leadership and position != "dop_coordinator":
                if position == "homeroom_teacher":
                    linked = db.execute("SELECT 1 FROM users WHERE id=? AND role='student' AND class_id=?",
                                        (body.target_id, scope_class)).fetchone()
                else:
                    linked = db.execute("SELECT 1 FROM teacher_subject_assignments WHERE student_id=? AND staff_id=?",
                                        (body.target_id, actor["id"])).fetchone()
                if target["role"] != "student" or not linked:
                    raise HTTPException(status_code=403, detail="Student is outside this staff member's assigned scope")
            if actor["role"] == "mentor" and not is_school_leadership:
                linked = db.execute("SELECT 1 FROM student_links WHERE student_id=? AND staff_id=? AND link_type='mentor'",
                                    (body.target_id, actor["id"])).fetchone()
                if target["role"] != "student" or not linked:
                    raise HTTPException(status_code=403, detail="Student is not assigned to this mentor")
        elif body.target_type == "class":
            if position == "homeroom_teacher" and core.normalize_class_id(body.target_id) != core.normalize_class_id(scope_class):
                raise HTTPException(status_code=403, detail="Homeroom teacher may publish only to their assigned class")
            class_rows = db.execute("SELECT class_id FROM users WHERE role='student' AND active=1 AND class_id IS NOT NULL").fetchall()
            target_key = core.normalize_class_id(body.target_id)
            if not any(core.normalize_class_id(row["class_id"]) == target_key for row in class_rows):
                raise HTTPException(status_code=404, detail="Target class not found")
        elif body.target_type == "group":
            target = db.execute("SELECT id FROM notification_groups WHERE id=?", (body.target_id,)).fetchone()
            if not target:
                raise HTTPException(status_code=404, detail="Target group not found")
            if not is_school_leadership:
                non_students = db.execute(
                    "SELECT 1 FROM notification_group_members m JOIN users u ON u.id=m.user_id "
                    "WHERE m.group_id=? AND u.active=1 AND u.role!='student' LIMIT 1",
                    (body.target_id,)
                ).fetchone()
                if non_students:
                    raise HTTPException(status_code=403, detail="This group includes staff accounts and requires school leadership to broadcast")
        notification_id = secrets.token_urlsafe(12)
        created_at = _now()
        delivery_status = "scheduled" if scheduled_at and scheduled_at > created_at else "queued"
        db.execute("INSERT INTO notifications(id,title,body,kind,target_type,target_id,created_by,created_at,scheduled_at,expires_at,delivery_status) VALUES(?,?,?,?,?,?,?,?,?,?,?)",
                   (notification_id, body.title, body.body, body.kind, body.target_type, body.target_id, actor["id"], created_at, scheduled_at, expires_at, delivery_status))
    core._audit(actor["id"], "notification.created", notification_id,
                {"kind": body.kind, "target_type": body.target_type, "target_id": body.target_id})
    return {"id": notification_id, "title": body.title, "body": body.body, "kind": body.kind,
            "target_type": body.target_type, "target_id": body.target_id, "created_at": created_at,
            "scheduled_at": scheduled_at, "expires_at": expires_at, "delivery_status": delivery_status, "push_status": "pending"}


@router.get("/admin/notifications")
def list_admin_notifications(limit: int = 100,
                             actor: dict[str, Any] = Depends(core.current_user)) -> dict[str, Any]:
    """Return recent delivery records to school leadership without exposing device tokens."""
    from . import rbac_api
    position, _ = (None, None) if actor["role"] == "admin" else rbac_api._position(actor["id"])
    if actor["role"] != "admin" and position not in {"director", "deputy"}:
        raise HTTPException(status_code=403, detail="School leadership permission required")
    limit = max(1, min(limit, 200))
    with core._db() as db:
        rows = db.execute(
            "SELECT id,title,body,kind,target_type,target_id,created_by,created_at,scheduled_at,expires_at,"
            "delivery_status,push_status,delivered_count,delivery_attempts,last_error_code "
            "FROM notifications WHERE target_type='all' ORDER BY created_at DESC LIMIT ?", (limit,)
        ).fetchall()
    return {"data": [dict(row) for row in rows]}


@router.delete("/admin/notifications/{notification_id}")
def cancel_notification(notification_id: str,
                        actor: dict[str, Any] = Depends(core.current_user)) -> dict[str, Any]:
    """Cancel a notification in the in-app feed and stop any not-yet-started delivery."""
    from . import rbac_api
    position, _ = (None, None) if actor["role"] == "admin" else rbac_api._position(actor["id"])
    if actor["role"] != "admin" and position not in {"director", "deputy"}:
        raise HTTPException(status_code=403, detail="School leadership permission required")
    with core._db() as db:
        row = db.execute(
            "SELECT id,target_type,delivery_status,push_status FROM notifications WHERE id=?", (notification_id,)
        ).fetchone()
        # This endpoint manages only school-wide broadcasts. Do not let a leadership
        # account use it to inspect or cancel private, class, or group notifications.
        if not row or row["target_type"] != "all":
            raise HTTPException(status_code=404, detail="School-wide notification not found")
        if row["delivery_status"] == "processing":
            raise HTTPException(status_code=409, detail="Notification delivery is already in progress; retry after it finishes")
        already_sent = row["delivery_status"] in {"sent", "partial"} or row["push_status"] in {"sent", "partial"}
        db.execute(
            "UPDATE notifications SET delivery_status='cancelled',"
            "push_status=CASE WHEN push_status IN ('sent','partial') THEN push_status ELSE 'cancelled' END,"
            "next_attempt_at=NULL WHERE id=?", (notification_id,)
        )
    core._audit(actor["id"], "notification.cancelled", notification_id, {"push_already_sent": already_sent})
    return {
        "status": "cancelled",
        "notification_id": notification_id,
        "push_already_sent": already_sent,
        "note": "A push already delivered to a device cannot be recalled." if already_sent else "Pending delivery cancelled.",
    }


@router.get("/notifications")
def list_notifications(actor: dict[str, Any] = Depends(core.current_user)) -> dict[str, Any]:
    from . import rbac_api
    _, position_class = rbac_api._position(actor["id"])
    actor_class = actor.get("class_id") or position_class
    normalized_actor_class = core.normalize_class_id(actor_class)
    now = _now()
    with core._db() as db:
        # Filter recipients in SQL before applying the page limit. Limiting the
        # global table first could let 200 unrelated class/group notices hide
        # an older personal notification from this user's feed.
        recipient_conditions = [
            "target_type='all'",
            "(target_type='user' AND target_id=?)",
            "(target_type='group' AND target_id IN "
            "(SELECT group_id FROM notification_group_members WHERE user_id=?))",
        ]
        parameters: list[Any] = [now, now, actor["id"], actor["id"]]

        if normalized_actor_class:
            class_rows = db.execute(
                "SELECT DISTINCT target_id FROM notifications "
                "WHERE target_type='class' AND target_id IS NOT NULL"
            ).fetchall()
            matching_class_ids = [
                row["target_id"]
                for row in class_rows
                if core.normalize_class_id(row["target_id"]) == normalized_actor_class
            ]
            if matching_class_ids:
                placeholders = ",".join("?" for _ in matching_class_ids)
                recipient_conditions.append(
                    f"(target_type='class' AND target_id IN ({placeholders}))"
                )
                parameters.extend(matching_class_ids)

        rows = db.execute(
            "SELECT * FROM notifications "
            "WHERE (scheduled_at IS NULL OR scheduled_at<=?) "
            "AND (expires_at IS NULL OR expires_at>?) "
            "AND delivery_status NOT IN ('processing','cancelled','expired') "
            "AND (" + " OR ".join(recipient_conditions) + ") "
            "ORDER BY created_at DESC LIMIT 200",
            parameters,
        ).fetchall()
    return {"data": [dict(row) for row in rows]}
