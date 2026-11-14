"""School polls: staff create them, students (and staff) vote once per poll.

Results are aggregated only: other users' individual choices are never exposed.
"""
from __future__ import annotations

import secrets
from datetime import datetime, timezone
from typing import Any

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from . import school_api as core

router = APIRouter(prefix="/api/v2/polls", tags=["polls"])

STAFF_ROLES = ("admin", "teacher", "mentor")


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _parse_time(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        raise HTTPException(status_code=422, detail="closes_at must be an ISO date-time")
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def _init() -> None:
    with core._db() as db:
        db.executescript("""
        CREATE TABLE IF NOT EXISTS polls (
          id TEXT PRIMARY KEY, title TEXT NOT NULL, description TEXT NOT NULL DEFAULT '',
          scope TEXT NOT NULL CHECK(scope IN ('school','class')), class_id TEXT,
          multiple INTEGER NOT NULL DEFAULT 0, closed INTEGER NOT NULL DEFAULT 0,
          created_by TEXT NOT NULL REFERENCES users(id), created_at TEXT NOT NULL, closes_at TEXT
        );
        CREATE TABLE IF NOT EXISTS poll_options (
          id TEXT PRIMARY KEY, poll_id TEXT NOT NULL REFERENCES polls(id) ON DELETE CASCADE,
          text TEXT NOT NULL, position INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS poll_votes (
          poll_id TEXT NOT NULL REFERENCES polls(id) ON DELETE CASCADE,
          option_id TEXT NOT NULL REFERENCES poll_options(id) ON DELETE CASCADE,
          user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          created_at TEXT NOT NULL, PRIMARY KEY(poll_id, option_id, user_id)
        );
        CREATE INDEX IF NOT EXISTS idx_poll_votes_user ON poll_votes(user_id);
        CREATE INDEX IF NOT EXISTS idx_polls_created ON polls(created_at);
        """)


async def init_polls() -> None:
    _init()


class PollCreate(BaseModel):
    title: str = Field(min_length=1, max_length=160)
    description: str = Field(default="", max_length=1000)
    options: list[str] = Field(min_length=2, max_length=10)
    scope: str = Field(default="school", pattern="^(school|class)$")
    class_id: str | None = Field(default=None, max_length=32)
    multiple: bool = False
    closes_at: str | None = None


class VoteBody(BaseModel):
    option_ids: list[str] = Field(min_length=1, max_length=10)


def _is_open(row: Any) -> bool:
    if row["closed"]:
        return False
    closes = _parse_time(row["closes_at"])
    return closes is None or closes > datetime.now(timezone.utc)


def _can_see(actor: dict[str, Any], row: Any) -> bool:
    if actor["role"] == "admin" or row["created_by"] == actor["id"]:
        return True
    if row["scope"] == "school":
        return True
    mine = core.normalize_class_id(actor.get("class_id") or "")
    return bool(mine) and mine == core.normalize_class_id(row["class_id"] or "")


def _serialize(db, row: Any, actor: dict[str, Any]) -> dict[str, Any]:
    options = db.execute(
        "SELECT id,text FROM poll_options WHERE poll_id=? ORDER BY position", (row["id"],)
    ).fetchall()
    counts = {
        r["option_id"]: r["n"]
        for r in db.execute(
            "SELECT option_id, COUNT(*) AS n FROM poll_votes WHERE poll_id=? GROUP BY option_id",
            (row["id"],),
        ).fetchall()
    }
    mine = [
        r["option_id"]
        for r in db.execute(
            "SELECT option_id FROM poll_votes WHERE poll_id=? AND user_id=?",
            (row["id"], actor["id"]),
        ).fetchall()
    ]
    voters = db.execute(
        "SELECT COUNT(DISTINCT user_id) AS n FROM poll_votes WHERE poll_id=?", (row["id"],)
    ).fetchone()["n"]
    is_open = _is_open(row)
    can_manage = actor["role"] == "admin" or row["created_by"] == actor["id"]
    # Results are shown after voting, after closing, or to the poll's managers.
    show_results = bool(mine) or not is_open or can_manage
    return {
        "id": row["id"],
        "title": row["title"],
        "description": row["description"],
        "scope": row["scope"],
        "class_id": row["class_id"] or "",
        "multiple": bool(row["multiple"]),
        "open": is_open,
        "closes_at": row["closes_at"],
        "created_at": row["created_at"],
        "can_manage": can_manage,
        "my_option_ids": mine,
        "total_voters": voters if show_results else None,
        "options": [
            {"id": o["id"], "text": o["text"], "votes": counts.get(o["id"], 0) if show_results else None}
            for o in options
        ],
    }


def create_poll_for(actor: dict[str, Any], body: PollCreate) -> dict[str, Any]:
    options = [o.strip() for o in body.options if o.strip()]
    if len(options) != len(body.options) or len(set(x.lower() for x in options)) != len(options):
        raise HTTPException(status_code=422, detail="Options must be non-empty and unique")
    if any(len(o) > 120 for o in options):
        raise HTTPException(status_code=422, detail="Option is too long")
    class_id = None
    if body.scope == "class":
        class_id = core.normalize_class_id(body.class_id or actor.get("class_id") or "")
        if not class_id:
            raise HTTPException(status_code=422, detail="class_id is required for a class poll")
    closes = _parse_time(body.closes_at)
    if closes is not None and closes <= datetime.now(timezone.utc):
        raise HTTPException(status_code=422, detail="closes_at must be in the future")
    poll_id = secrets.token_urlsafe(12)
    with core._db() as db:
        db.execute(
            "INSERT INTO polls(id,title,description,scope,class_id,multiple,created_by,created_at,closes_at)"
            " VALUES(?,?,?,?,?,?,?,?,?)",
            (poll_id, body.title.strip(), body.description.strip(), body.scope, class_id,
             int(body.multiple), actor["id"], _now(), closes.isoformat() if closes else None),
        )
        for position, text in enumerate(options):
            db.execute(
                "INSERT INTO poll_options(id,poll_id,text,position) VALUES(?,?,?,?)",
                (secrets.token_urlsafe(8), poll_id, text, position),
            )
    core._audit(actor["id"], "poll.created", poll_id, {"scope": body.scope})
    with core._db() as db:
        row = db.execute("SELECT * FROM polls WHERE id=?", (poll_id,)).fetchone()
        return _serialize(db, row, actor)


def list_polls_for(actor: dict[str, Any]) -> dict[str, Any]:
    with core._db() as db:
        rows = db.execute("SELECT * FROM polls ORDER BY created_at DESC LIMIT 200").fetchall()
        data = [_serialize(db, row, actor) for row in rows if _can_see(actor, row)]
    return {"data": data}


def vote_for(actor: dict[str, Any], poll_id: str, body: VoteBody) -> dict[str, Any]:
    with core._db() as db:
        row = db.execute("SELECT * FROM polls WHERE id=?", (poll_id,)).fetchone()
        if row is None or not _can_see(actor, row):
            raise HTTPException(status_code=404, detail="Poll not found")
        if not _is_open(row):
            raise HTTPException(status_code=409, detail="Poll is closed")
        chosen = list(dict.fromkeys(body.option_ids))
        if not row["multiple"] and len(chosen) != 1:
            raise HTTPException(status_code=422, detail="Choose exactly one option")
        valid = {r["id"] for r in db.execute("SELECT id FROM poll_options WHERE poll_id=?", (poll_id,)).fetchall()}
        if not set(chosen) <= valid:
            raise HTTPException(status_code=422, detail="Unknown option")
        db.execute("DELETE FROM poll_votes WHERE poll_id=? AND user_id=?", (poll_id, actor["id"]))
        for option_id in chosen:
            db.execute(
                "INSERT INTO poll_votes(poll_id,option_id,user_id,created_at) VALUES(?,?,?,?)",
                (poll_id, option_id, actor["id"], _now()),
            )
        return _serialize(db, row, actor)


def _managed(db, actor: dict[str, Any], poll_id: str) -> Any:
    row = db.execute("SELECT * FROM polls WHERE id=?", (poll_id,)).fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail="Poll not found")
    if actor["role"] != "admin" and row["created_by"] != actor["id"]:
        raise HTTPException(status_code=403, detail="Only the author or an administrator can manage this poll")
    return row


def close_poll_for(actor: dict[str, Any], poll_id: str) -> dict[str, Any]:
    with core._db() as db:
        _managed(db, actor, poll_id)
        db.execute("UPDATE polls SET closed=1 WHERE id=?", (poll_id,))
        row = db.execute("SELECT * FROM polls WHERE id=?", (poll_id,)).fetchone()
        result = _serialize(db, row, actor)
    core._audit(actor["id"], "poll.closed", poll_id)
    return result


def delete_poll_for(actor: dict[str, Any], poll_id: str) -> dict[str, str]:
    with core._db() as db:
        _managed(db, actor, poll_id)
        db.execute("DELETE FROM polls WHERE id=?", (poll_id,))
    core._audit(actor["id"], "poll.deleted", poll_id)
    return {"status": "deleted"}


@router.post("", status_code=201)
def create_poll(body: PollCreate, actor: dict[str, Any] = Depends(core.require_roles(*STAFF_ROLES))) -> dict[str, Any]:
    return create_poll_for(actor, body)


@router.get("")
def list_polls(actor: dict[str, Any] = Depends(core.current_user)) -> dict[str, Any]:
    return list_polls_for(actor)


@router.post("/{poll_id}/vote")
def vote(poll_id: str, body: VoteBody, actor: dict[str, Any] = Depends(core.current_user)) -> dict[str, Any]:
    return vote_for(actor, poll_id, body)


@router.post("/{poll_id}/close")
def close_poll(poll_id: str, actor: dict[str, Any] = Depends(core.current_user)) -> dict[str, Any]:
    return close_poll_for(actor, poll_id)


@router.delete("/{poll_id}")
def delete_poll(poll_id: str, actor: dict[str, Any] = Depends(core.current_user)) -> dict[str, str]:
    return delete_poll_for(actor, poll_id)
