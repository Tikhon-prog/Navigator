"""School SSO bridge using the school's OIDC access-token/userinfo endpoint.

The mobile app performs OIDC Authorization Code + PKCE with the school IdP, then
sends its short-lived access token here. The server validates it by calling the
configured HTTPS userinfo endpoint and only accepts explicitly linked subjects.
"""
from __future__ import annotations

import os
import re
import secrets
from typing import Any

import requests
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from . import school_api as core

router = APIRouter(prefix="/api/v2", tags=["school SSO"])


class SsoLoginBody(BaseModel):
    access_token: str = Field(min_length=20, max_length=8192)


class SsoLinkBody(BaseModel):
    username: str = Field(min_length=1, max_length=120)
    subject: str = Field(min_length=1, max_length=512)


def _userinfo(access_token: str) -> dict[str, Any]:
    endpoint = os.getenv("NAVIGATOR_OIDC_USERINFO_URL", "").strip()
    issuer = os.getenv("NAVIGATOR_OIDC_ISSUER", "").rstrip("/")
    if not endpoint or not issuer:
        raise HTTPException(status_code=503, detail="School SSO is not configured")
    if not issuer.startswith("https://") and not issuer.startswith("http://localhost"):
        raise HTTPException(status_code=503, detail="SSO issuer must use HTTPS")
    if not endpoint.startswith("https://") and not endpoint.startswith("http://localhost"):
        raise HTTPException(status_code=503, detail="SSO userinfo endpoint must use HTTPS")
    try:
        response = requests.get(
            endpoint,
            headers={"Authorization": f"Bearer {access_token}", "Accept": "application/json"},
            timeout=8,
        )
        if response.status_code != 200:
            raise HTTPException(status_code=401, detail="School SSO token was rejected")
        claims = response.json()
        if not isinstance(claims, dict) or not isinstance(claims.get("sub"), str) or not claims["sub"]:
            raise HTTPException(status_code=401, detail="School SSO returned no stable subject")
        # If the provider exposes issuer in userinfo, require it to match the configured issuer.
        returned_issuer = claims.get("iss")
        if returned_issuer and str(returned_issuer).rstrip("/") != issuer:
            raise HTTPException(status_code=401, detail="School SSO issuer mismatch")
        return claims
    except HTTPException:
        raise
    except (requests.RequestException, ValueError):
        raise HTTPException(status_code=502, detail="School SSO is temporarily unavailable")


@router.on_event("startup")
def init_sso_tables() -> None:
    with core._db() as db:
        db.execute("""
            CREATE TABLE IF NOT EXISTS sso_identities (
                issuer TEXT NOT NULL,
                subject TEXT NOT NULL,
                user_id TEXT NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
                linked_at TEXT NOT NULL,
                PRIMARY KEY(issuer, subject)
            )
        """)


def _link_or_provision(claims: dict[str, Any], issuer: str):
    """Optionally map a trusted school claim to an existing account or provision one."""
    username_claim = os.getenv("NAVIGATOR_OIDC_USERNAME_CLAIM", "preferred_username").strip()
    username = claims.get(username_claim)
    if not isinstance(username, str) or not username.strip():
        return None
    username = username.strip()
    if not re.fullmatch(r"[A-Za-z0-9_.@-]{3,120}", username):
        return None

    auto_link = os.getenv("NAVIGATOR_OIDC_AUTO_LINK_USERNAME", "false").strip().lower() in {"1", "true", "yes", "on"}
    auto_provision = os.getenv("NAVIGATOR_OIDC_AUTO_PROVISION", "false").strip().lower() in {"1", "true", "yes", "on"}
    role_claim = os.getenv("NAVIGATOR_OIDC_ROLE_CLAIM", "role").strip()
    raw_role = claims.get(role_claim)
    if isinstance(raw_role, list):
        raw_role = next((value for value in raw_role if isinstance(value, str)), "")
    role_text = str(raw_role or "").strip().lower()
    role_aliases = {
        "student": "student", "students": "student", "ученик": "student", "ученица": "student",
        "teacher": "teacher", "teachers": "teacher", "учитель": "teacher", "педагог": "teacher",
        "mentor": "mentor", "наставник": "mentor",
        "director": "director", "principal": "director", "директор": "director",
        "deputy": "deputy", "vice_principal": "deputy", "завуч": "deputy",
        "homeroom_teacher": "homeroom_teacher", "class_teacher": "homeroom_teacher", "классный руководитель": "homeroom_teacher",
        "dop_coordinator": "dop_coordinator", "mentor_coordinator": "mentor_coordinator",
        "librarian": "librarian", "библиотекарь": "librarian",
        "admin": "admin", "administrator": "admin", "администратор": "admin",
    }
    mapped_role = role_aliases.get(role_text)
    class_claim = os.getenv("NAVIGATOR_OIDC_CLASS_CLAIM", "class_id").strip()
    class_id = str(claims.get(class_claim) or "").strip() or None
    display_claim = os.getenv("NAVIGATOR_OIDC_DISPLAY_NAME_CLAIM", "name").strip()
    display_name = str(claims.get(display_claim) or claims.get("given_name") or username).strip()[:160]

    with core._db() as db:
        existing = db.execute("SELECT * FROM users WHERE username=? COLLATE NOCASE AND active=1", (username,)).fetchone()
        if existing:
            if not auto_link:
                return None
            try:
                db.execute("INSERT INTO sso_identities(issuer,subject,user_id,linked_at) VALUES(?,?,?,?)",
                           (issuer, claims["sub"], existing["id"], core._utc_now()))
            except Exception:
                return None
            return existing

        if not auto_provision or not mapped_role:
            return None
        if mapped_role == "admin" and os.getenv("NAVIGATOR_OIDC_ALLOW_ADMIN_PROVISION", "false").strip().lower() not in {"1", "true", "yes", "on"}:
            return None
        if mapped_role == "student" and not class_id:
            return None
        if mapped_role == "homeroom_teacher" and not class_id:
            return None

        base_role = mapped_role if mapped_role in {"student", "mentor", "admin"} else "teacher"
        user_id = secrets.token_urlsafe(12)
        random_password = secrets.token_urlsafe(48)
        db.execute(
            "INSERT INTO users(id,username,password_hash,role,display_name,class_id,created_at) VALUES(?,?,?,?,?,?,?)",
            (user_id, username, core._hash_password(random_password), base_role, display_name, class_id, core._utc_now())
        )
        position = mapped_role if mapped_role in {"director", "deputy", "homeroom_teacher", "dop_coordinator", "mentor_coordinator", "librarian"} else None
        if position:
            db.execute(
                "INSERT INTO staff_positions(user_id,position,scope_class,assigned_by,updated_at) VALUES(?,?,?,?,?)",
                (user_id, position, class_id if position == "homeroom_teacher" else None, None, core._utc_now())
            )
        db.execute("INSERT INTO sso_identities(issuer,subject,user_id,linked_at) VALUES(?,?,?,?)",
                   (issuer, claims["sub"], user_id, core._utc_now()))
        return db.execute("SELECT * FROM users WHERE id=?", (user_id,)).fetchone()


@router.post("/auth/sso")
def sso_login(body: SsoLoginBody) -> dict[str, Any]:
    issuer = os.getenv("NAVIGATOR_OIDC_ISSUER", "").rstrip("/")
    claims = _userinfo(body.access_token)
    with core._db() as db:
        identity = db.execute(
            "SELECT u.* FROM sso_identities i JOIN users u ON u.id=i.user_id "
            "WHERE i.issuer=? AND i.subject=? AND u.active=1",
            (issuer, claims["sub"]),
        ).fetchone()
    if not identity:
        # Auto-link/provision is opt-in and uses only claims returned by the trusted
        # configured IdP's HTTPS UserInfo endpoint, never a client-supplied profile.
        identity = _link_or_provision(claims, issuer)
    if not identity:
        raise HTTPException(status_code=403, detail="SSO identity is not linked or auto-provisioning claims are incomplete; ask the school administrator")
    result = core._issue_session(identity)
    core._audit(identity["id"], "auth.sso_login")
    return result


@router.post("/admin/sso-identities", status_code=201)
def link_sso_identity(body: SsoLinkBody, actor: dict[str, Any] = Depends(core.require_roles("admin"))) -> dict[str, str]:
    issuer = os.getenv("NAVIGATOR_OIDC_ISSUER", "").rstrip("/")
    if not issuer:
        raise HTTPException(status_code=503, detail="School SSO is not configured")
    with core._db() as db:
        user = db.execute("SELECT id FROM users WHERE username=? COLLATE NOCASE AND active=1", (body.username,)).fetchone()
        if not user:
            raise HTTPException(status_code=404, detail="Active local account not found")
        try:
            db.execute("INSERT INTO sso_identities(issuer,subject,user_id,linked_at) VALUES(?,?,?,?)",
                       (issuer, body.subject, user["id"], core._utc_now()))
        except Exception:
            raise HTTPException(status_code=409, detail="SSO subject or local account is already linked")
    core._audit(actor["id"], "sso.identity_linked", user["id"], {"issuer": issuer})
    return {"status": "linked", "user_id": user["id"]}
