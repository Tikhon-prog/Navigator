"""School SSO bridge using the school's OIDC access-token/userinfo endpoint.

The mobile app performs OIDC Authorization Code + PKCE with the school IdP, then
sends its short-lived access token here. The server validates it by calling the
configured HTTPS userinfo endpoint and only accepts explicitly linked subjects.
"""
from __future__ import annotations

import os
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
        # Never auto-link by email/username: that can let an unverified claim take over an account.
        raise HTTPException(status_code=403, detail="SSO identity is not linked; ask the school administrator")
    token = core._make_token(identity)
    core._audit(identity["id"], "auth.sso_login")
    return {"access_token": token, "token_type": "bearer", "expires_in": core.TOKEN_TTL_SECONDS,
            "user": core._public_user(identity)}


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
