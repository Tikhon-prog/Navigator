"""Production-oriented Navigator API scaffold.

Run locally:
  NAVIGATOR_JWT_SECRET="<random 48+ chars>" uvicorn server_app:app --app-dir backend --host 127.0.0.1 --port 8000

For production, set APP_ENV=production, NAVIGATOR_JWT_SECRET, DATABASE_URL,
BOOTSTRAP_ADMIN_KEY and (optionally) FIREBASE_SERVICE_ACCOUNT_JSON in the host's
secret manager. Never put secrets in the Flutter app or source control.
"""
import hashlib
import json
import logging
import os
import secrets
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Annotated, Literal

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError, VerifyMismatchError
from fastapi import Depends, FastAPI, Header, HTTPException, Request, Response, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, Field
from sqlalchemy import (
    Boolean, DateTime, ForeignKey, Integer, String, Text, UniqueConstraint,
    create_engine, select,
)
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import DeclarativeBase, Mapped, Session, mapped_column, sessionmaker
from sqlalchemy.pool import StaticPool

logger = logging.getLogger("navigator.server")
ROLES = {"admin", "mentor", "teacher", "student", "emergency_manager"}
ALERT_SEVERITIES = {"info", "warning", "critical"}
ALERT_TARGETS = {"all", "role", "class", "user"}
JWT_ISSUER = "navigator-school-api"
ACCESS_TOKEN_MINUTES = 30
LOGIN_FAILURE_LIMIT = 5
LOGIN_LOCK_MINUTES = 15
ph = PasswordHasher(time_cost=3, memory_cost=65536, parallelism=2, hash_len=32, salt_len=16)
bearer = HTTPBearer(auto_error=False)


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _normalise_dt(value: datetime | None) -> datetime | None:
    if value is None:
        return None
    return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value


class Base(DeclarativeBase):
    pass


class User(Base):
    __tablename__ = "users"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    login: Mapped[str] = mapped_column(String(120), unique=True, index=True)
    display_name: Mapped[str] = mapped_column(String(160))
    role: Mapped[str] = mapped_column(String(32), index=True)
    password_hash: Mapped[str] = mapped_column(String(512))
    active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class SchoolClass(Base):
    __tablename__ = "school_classes"
    id: Mapped[str] = mapped_column(String(80), primary_key=True)
    name: Mapped[str] = mapped_column(String(80), unique=True)
    grade: Mapped[str] = mapped_column(String(20), default="")


class MentorAssignment(Base):
    __tablename__ = "mentor_assignments"
    __table_args__ = (UniqueConstraint("mentor_id", "student_id", name="uq_mentor_student"),)
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    mentor_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    student_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)


class TeacherAssignment(Base):
    __tablename__ = "teacher_assignments"
    __table_args__ = (UniqueConstraint("teacher_id", "class_id", name="uq_teacher_class"),)
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    teacher_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    class_id: Mapped[str] = mapped_column(ForeignKey("school_classes.id", ondelete="CASCADE"), index=True)


class ClassMembership(Base):
    __tablename__ = "class_memberships"
    __table_args__ = (UniqueConstraint("student_id", "class_id", name="uq_student_class"),)
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    student_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    class_id: Mapped[str] = mapped_column(ForeignKey("school_classes.id", ondelete="CASCADE"), index=True)


class ScheduleRecord(Base):
    __tablename__ = "schedule_records"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    class_id: Mapped[str] = mapped_column(ForeignKey("school_classes.id", ondelete="CASCADE"), index=True)
    weekday: Mapped[int] = mapped_column(Integer)
    lesson_number: Mapped[int] = mapped_column(Integer)
    start_time: Mapped[str] = mapped_column(String(20), default="")
    subject: Mapped[str] = mapped_column(String(200))
    room: Mapped[str] = mapped_column(String(80), default="")
    teacher_name: Mapped[str] = mapped_column(String(160), default="")
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class SupplementRecord(Base):
    __tablename__ = "supplement_records"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    student_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    title: Mapped[str] = mapped_column(String(200))
    weekday: Mapped[int] = mapped_column(Integer)
    start_time: Mapped[str] = mapped_column(String(80), default="")
    end_time: Mapped[str] = mapped_column(String(80), default="")
    teacher_name: Mapped[str] = mapped_column(String(160), default="")
    room: Mapped[str] = mapped_column(String(80), default="")
    place: Mapped[str] = mapped_column(String(160), default="")
    group_name: Mapped[str] = mapped_column(String(160), default="")
    description: Mapped[str] = mapped_column(Text, default="")
    source: Mapped[str] = mapped_column(String(40), default="school")
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class AlertRecord(Base):
    __tablename__ = "school_alerts"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    title: Mapped[str] = mapped_column(String(180))
    body: Mapped[str] = mapped_column(String(3000))
    severity: Mapped[str] = mapped_column(String(20), index=True)
    target_type: Mapped[str] = mapped_column(String(20), index=True)
    target_value: Mapped[str] = mapped_column(String(160), default="")
    sender_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, index=True)
    fcm_status: Mapped[str] = mapped_column(String(40), default="pending")


class Device(Base):
    __tablename__ = "devices"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    token: Mapped[str] = mapped_column(String(4096), unique=True, index=True)
    platform: Mapped[str] = mapped_column(String(20), default="unknown")
    active: Mapped[bool] = mapped_column(Boolean, default=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class LoginAttempt(Base):
    __tablename__ = "login_attempts"
    key: Mapped[str] = mapped_column(String(64), primary_key=True)
    failures: Mapped[int] = mapped_column(Integer, default=0)
    locked_until: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class AuditEvent(Base):
    __tablename__ = "audit_events"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    actor_id: Mapped[str | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True)
    action: Mapped[str] = mapped_column(String(120))
    target_type: Mapped[str] = mapped_column(String(80), default="")
    target_id: Mapped[str] = mapped_column(String(160), default="")
    details_json: Mapped[str] = mapped_column(Text, default="{}")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, index=True)


class BootstrapBody(BaseModel):
    bootstrap_key: str = Field(min_length=1, max_length=512)
    login: str = Field(min_length=3, max_length=120)
    password: str = Field(min_length=12, max_length=256)
    display_name: str = Field(min_length=1, max_length=160)


class LoginBody(BaseModel):
    login: str = Field(min_length=1, max_length=120)
    password: str = Field(min_length=1, max_length=256)


class UserCreate(BaseModel):
    login: str = Field(min_length=3, max_length=120)
    password: str = Field(min_length=12, max_length=256)
    display_name: str = Field(min_length=1, max_length=160)
    role: Literal["admin", "mentor", "teacher", "student", "emergency_manager"]
    active: bool = True


class UserUpdate(BaseModel):
    display_name: str | None = Field(default=None, min_length=1, max_length=160)
    role: Literal["admin", "mentor", "teacher", "student", "emergency_manager"] | None = None
    active: bool | None = None
    password: str | None = Field(default=None, min_length=12, max_length=256)


class ClassCreate(BaseModel):
    id: str = Field(min_length=1, max_length=80)
    name: str = Field(min_length=1, max_length=80)
    grade: str = Field(default="", max_length=20)


class MentorLinkBody(BaseModel):
    mentor_id: str
    student_id: str


class TeacherLinkBody(BaseModel):
    teacher_id: str
    class_id: str


class ClassMembershipBody(BaseModel):
    student_id: str
    class_id: str


class ScheduleBody(BaseModel):
    class_id: str
    weekday: int = Field(ge=1, le=7)
    lesson_number: int = Field(ge=1, le=20)
    start_time: str = Field(default="", max_length=20)
    subject: str = Field(min_length=1, max_length=200)
    room: str = Field(default="", max_length=80)
    teacher_name: str = Field(default="", max_length=160)


class ScheduleUpdate(BaseModel):
    class_id: str | None = None
    weekday: int | None = Field(default=None, ge=1, le=7)
    lesson_number: int | None = Field(default=None, ge=1, le=20)
    start_time: str | None = Field(default=None, max_length=20)
    subject: str | None = Field(default=None, min_length=1, max_length=200)
    room: str | None = Field(default=None, max_length=80)
    teacher_name: str | None = Field(default=None, max_length=160)


class SupplementBody(BaseModel):
    student_id: str
    title: str = Field(min_length=1, max_length=200)
    weekday: int = Field(ge=1, le=7)
    start_time: str = Field(default="", max_length=80)
    end_time: str = Field(default="", max_length=80)
    teacher_name: str = Field(default="", max_length=160)
    room: str = Field(default="", max_length=80)
    place: str = Field(default="", max_length=160)
    group_name: str = Field(default="", max_length=160)
    description: str = Field(default="", max_length=3000)
    source: str = Field(default="school", max_length=40)


class SupplementUpdate(BaseModel):
    student_id: str | None = None
    title: str | None = Field(default=None, min_length=1, max_length=200)
    weekday: int | None = Field(default=None, ge=1, le=7)
    start_time: str | None = Field(default=None, max_length=80)
    end_time: str | None = Field(default=None, max_length=80)
    teacher_name: str | None = Field(default=None, max_length=160)
    room: str | None = Field(default=None, max_length=80)
    place: str | None = Field(default=None, max_length=160)
    group_name: str | None = Field(default=None, max_length=160)
    description: str | None = Field(default=None, max_length=3000)
    source: str | None = Field(default=None, max_length=40)


class DeviceBody(BaseModel):
    token: str = Field(min_length=16, max_length=4096)
    platform: Literal["android", "ios", "web", "unknown"] = "unknown"


class AlertBody(BaseModel):
    title: str = Field(min_length=1, max_length=180)
    body: str = Field(min_length=1, max_length=3000)
    severity: Literal["info", "warning", "critical"] = "info"
    target_type: Literal["all", "role", "class", "user"] = "all"
    target_value: str = Field(default="", max_length=160)


def _user_json(user: User) -> dict:
    return {
        "id": user.id, "login": user.login, "display_name": user.display_name,
        "role": user.role, "active": user.active, "created_at": user.created_at.isoformat(),
    }


def _class_json(item: SchoolClass) -> dict:
    return {"id": item.id, "name": item.name, "grade": item.grade}


def _schedule_json(item: ScheduleRecord) -> dict:
    return {
        "id": item.id, "class_id": item.class_id, "weekday": item.weekday,
        "lesson_number": item.lesson_number, "start_time": item.start_time,
        "subject": item.subject, "room": item.room, "teacher_name": item.teacher_name,
        "updated_at": item.updated_at.isoformat(),
    }


def _supplement_json(item: SupplementRecord) -> dict:
    return {
        "id": item.id, "student_id": item.student_id, "title": item.title,
        "weekday": item.weekday, "start_time": item.start_time, "end_time": item.end_time,
        "teacher_name": item.teacher_name, "room": item.room, "place": item.place,
        "group_name": item.group_name, "description": item.description,
        "source": item.source, "updated_at": item.updated_at.isoformat(),
    }


def _alert_json(item: AlertRecord) -> dict:
    return {
        "id": item.id, "title": item.title, "body": item.body, "severity": item.severity,
        "target_type": item.target_type, "created_at": item.created_at.isoformat(),
        "sender_id": item.sender_id, "fcm_status": item.fcm_status,
    }


def _audit(db: Session, actor_id: str | None, action: str, target_type: str = "",
           target_id: str = "", details: dict | None = None) -> None:
    db.add(AuditEvent(
        actor_id=actor_id, action=action, target_type=target_type, target_id=target_id,
        details_json=json.dumps(details or {}, ensure_ascii=False),
    ))


def _can_view_student(db: Session, viewer: User, student_id: str) -> bool:
    student = db.get(User, student_id)
    if student is None or student.role != "student":
        return False
    if viewer.role == "admin" or viewer.id == student_id:
        return True
    if viewer.role == "mentor":
        return db.scalar(select(MentorAssignment.id).where(
            MentorAssignment.mentor_id == viewer.id, MentorAssignment.student_id == student_id
        ).limit(1)) is not None
    if viewer.role == "teacher":
        assigned = select(TeacherAssignment.class_id).where(TeacherAssignment.teacher_id == viewer.id)
        student_classes = select(ClassMembership.class_id).where(ClassMembership.student_id == student_id)
        return db.scalar(select(TeacherAssignment.id).where(
            TeacherAssignment.teacher_id == viewer.id,
            TeacherAssignment.class_id.in_(student_classes),
        ).limit(1)) is not None
    return False



def _can_view_class(db: Session, viewer: User, class_id: str) -> bool:
    if db.get(SchoolClass, class_id) is None:
        return False
    if viewer.role == "admin":
        return True
    if viewer.role == "teacher":
        return db.scalar(select(TeacherAssignment.id).where(
            TeacherAssignment.teacher_id == viewer.id,
            TeacherAssignment.class_id == class_id,
        ).limit(1)) is not None
    if viewer.role == "student":
        return db.scalar(select(ClassMembership.id).where(
            ClassMembership.student_id == viewer.id,
            ClassMembership.class_id == class_id,
        ).limit(1)) is not None
    if viewer.role == "mentor":
        return db.scalar(select(MentorAssignment.id).join(
            ClassMembership, ClassMembership.student_id == MentorAssignment.student_id
        ).where(
            MentorAssignment.mentor_id == viewer.id,
            ClassMembership.class_id == class_id,
        ).limit(1)) is not None
    return False


def _target_user_ids(db: Session, alert: AlertRecord) -> set[str]:
    if alert.target_type == "all":
        return {u.id for u in db.scalars(select(User).where(User.active.is_(True)))}
    if alert.target_type == "role":
        return {u.id for u in db.scalars(select(User).where(
            User.active.is_(True), User.role == alert.target_value
        ))}
    if alert.target_type == "user":
        user = db.get(User, alert.target_value)
        return {user.id} if user is not None and user.active else set()
    if alert.target_type == "class":
        student_ids = set(db.scalars(select(ClassMembership.student_id).where(
            ClassMembership.class_id == alert.target_value
        )))
        teacher_ids = set(db.scalars(select(TeacherAssignment.teacher_id).where(
            TeacherAssignment.class_id == alert.target_value
        )))
        return student_ids | teacher_ids
    return set()


def _alert_visible(db: Session, user: User, alert: AlertRecord) -> bool:
    if alert.target_type == "all":
        return True
    if alert.target_type == "role":
        return user.role == alert.target_value
    if alert.target_type == "user":
        return user.id == alert.target_value
    if alert.target_type == "class":
        if user.role == "teacher":
            return db.scalar(select(TeacherAssignment.id).where(
                TeacherAssignment.teacher_id == user.id,
                TeacherAssignment.class_id == alert.target_value,
            ).limit(1)) is not None
        return user.role == "student" and db.scalar(select(ClassMembership.id).where(
            ClassMembership.student_id == user.id,
            ClassMembership.class_id == alert.target_value,
        ).limit(1)) is not None
    return False


def _send_fcm(firebase_app, tokens: list[str], alert: AlertRecord) -> tuple[str, int, int]:
    if firebase_app is None:
        return "not_configured", 0, 0
    if not tokens:
        return "no_registered_devices", 0, 0
    try:
        from firebase_admin import messaging
        success = 0
        failure = 0
        for offset in range(0, len(tokens), 500):
            batch_tokens = tokens[offset:offset + 500]
            message = messaging.MulticastMessage(
                tokens=batch_tokens,
                notification=messaging.Notification(title=alert.title, body=alert.body),
                data={"alert_id": alert.id, "severity": alert.severity, "category": "school_alert"},
                android=messaging.AndroidConfig(
                    priority="high" if alert.severity == "critical" else "normal"
                ),
                apns=messaging.APNSConfig(headers={
                    "apns-priority": "10" if alert.severity == "critical" else "5"
                }),
            )
            result = messaging.send_each_for_multicast(message, app=firebase_app)
            success += result.success_count
            failure += result.failure_count
        return ("sent" if failure == 0 else "partial" if success else "failed"), success, failure
    except Exception:
        logger.exception("FCM delivery failed; details are kept server-side")
        return "failed", 0, len(tokens)


def create_app(
    database_url: str | None = None,
    jwt_secret: str | None = None,
    bootstrap_admin_key: str | None = None,
    firebase_app=None,
) -> FastAPI:
    """Factory allows isolated test databases; production settings come from env."""
    secret = jwt_secret or os.getenv("NAVIGATOR_JWT_SECRET")
    if not secret:
        if os.getenv("APP_ENV", "").lower() == "production":
            raise RuntimeError("NAVIGATOR_JWT_SECRET is required in production")
        secret = secrets.token_urlsafe(48)
    if len(secret) < 32:
        raise RuntimeError("NAVIGATOR_JWT_SECRET must contain at least 32 characters")
    bootstrap_key = bootstrap_admin_key if bootstrap_admin_key is not None else os.getenv("BOOTSTRAP_ADMIN_KEY", "")
    db_url = database_url or os.getenv(
        "DATABASE_URL",
        f"sqlite:///{(Path(__file__).resolve().parent / 'navigator_server.sqlite3').as_posix()}",
    )
    engine_options = {"pool_pre_ping": True}
    if db_url in {"sqlite://", "sqlite:///:memory:", "sqlite+pysqlite:///:memory:"}:
        engine_options.update({"connect_args": {"check_same_thread": False}, "poolclass": StaticPool})
    elif db_url.startswith("sqlite:"):
        engine_options["connect_args"] = {"check_same_thread": False}
    engine = create_engine(db_url, **engine_options)
    factory = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)
    Base.metadata.create_all(engine)
    app = FastAPI(
        title="Navigator School API",
        version="0.1.0",
        description="Role-based school API scaffold: mentees, schedules, supplements and school-wide alerts.",
    )
    app.state.db_factory = factory
    app.state.engine = engine
    app.state.firebase_app = firebase_app

    if app.state.firebase_app is None:
        credentials_json = os.getenv("FIREBASE_SERVICE_ACCOUNT_JSON", "")
        if credentials_json.strip():
            try:
                import firebase_admin
                from firebase_admin import credentials
                certificate = credentials.Certificate(json.loads(credentials_json))
                app.state.firebase_app = firebase_admin.initialize_app(
                    certificate, name="navigator-" + uuid.uuid4().hex
                )
            except Exception:
                logger.exception("Firebase Admin could not be configured; API remains available without push")
                app.state.firebase_app = None

    def get_db():
        db = factory()
        try:
            yield db
        finally:
            db.close()

    def current_user(
        credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)],
        db: Annotated[Session, Depends(get_db)],
    ) -> User:
        if credentials is None:
            raise HTTPException(status_code=401, detail="Authentication required",
                                headers={"WWW-Authenticate": "Bearer"})
        try:
            payload = jwt.decode(
                credentials.credentials, secret, algorithms=["HS256"], issuer=JWT_ISSUER,
                options={"require": ["exp", "iat", "sub", "iss"]},
            )
            user_id = str(payload["sub"])
        except (jwt.InvalidTokenError, KeyError, TypeError):
            raise HTTPException(status_code=401, detail="Invalid or expired access token",
                                headers={"WWW-Authenticate": "Bearer"})
        user = db.get(User, user_id)
        if user is None or not user.active:
            raise HTTPException(status_code=401, detail="Account is unavailable")
        return user

    def require_roles(*allowed: str):
        def dependency(user: Annotated[User, Depends(current_user)]) -> User:
            if user.role not in allowed:
                raise HTTPException(status_code=403, detail="Insufficient permissions")
            return user
        return dependency

    def make_tokens(user: User) -> dict:
        now = utcnow()
        token = jwt.encode({
            "sub": user.id, "role": user.role, "iss": JWT_ISSUER,
            "iat": now, "exp": now + timedelta(minutes=ACCESS_TOKEN_MINUTES),
            "jti": secrets.token_urlsafe(16),
        }, secret, algorithm="HS256")
        return {"access_token": token, "token_type": "bearer",
                "expires_in": ACCESS_TOKEN_MINUTES * 60, "user": _user_json(user)}

    @app.get("/")
    def root():
        return {"name": "Navigator School API", "status": "ok", "api_version": "v1"}

    @app.get("/api/v1/health")
    def health(db: Annotated[Session, Depends(get_db)]):
        db.execute(select(1))
        return {"status": "ok", "database": "ok", "firebase": "configured" if app.state.firebase_app else "not_configured"}

    @app.post("/api/v1/auth/bootstrap", status_code=status.HTTP_201_CREATED)
    def bootstrap(body: BootstrapBody, request: Request, db: Annotated[Session, Depends(get_db)]):
        if not bootstrap_key or not secrets.compare_digest(body.bootstrap_key, bootstrap_key):
            raise HTTPException(status_code=403, detail="Bootstrap is disabled or key is invalid")
        if db.scalar(select(User.id).limit(1)) is not None:
            raise HTTPException(status_code=409, detail="Initial administrator already exists")
        login = body.login.strip().casefold()
        if not login:
            raise HTTPException(status_code=422, detail="Login is required")
        user = User(login=login, display_name=body.display_name.strip(), role="admin",
                    password_hash=ph.hash(body.password), active=True)
        try:
            db.add(user)
            db.flush()
            _audit(db, user.id, "bootstrap_admin_created", "user", user.id)
            db.commit()
            db.refresh(user)
        except IntegrityError:
            db.rollback()
            raise HTTPException(status_code=409, detail="Initial administrator already exists")
        return make_tokens(user)

    @app.post("/api/v1/auth/login")
    def login(body: LoginBody, request: Request, db: Annotated[Session, Depends(get_db)]):
        login_name = body.login.strip().casefold()
        remote_ip = request.client.host if request.client else "unknown"
        attempt_key = hashlib.sha256(f"{login_name}|{remote_ip}".encode()).hexdigest()
        attempt = db.get(LoginAttempt, attempt_key)
        now = utcnow()
        if attempt and _normalise_dt(attempt.locked_until) and _normalise_dt(attempt.locked_until) > now:
            raise HTTPException(status_code=429, detail="Too many attempts. Try again later")
        user = db.scalar(select(User).where(User.login == login_name).limit(1))
        valid = False
        if user is not None and user.active:
            try:
                valid = ph.verify(user.password_hash, body.password)
            except (VerifyMismatchError, VerificationError, InvalidHashError):
                valid = False
        if not valid:
            if attempt is None:
                attempt = LoginAttempt(key=attempt_key, failures=0)
                db.add(attempt)
            attempt.failures += 1
            if attempt.failures >= LOGIN_FAILURE_LIMIT:
                attempt.locked_until = now + timedelta(minutes=LOGIN_LOCK_MINUTES)
                attempt.failures = 0
            db.commit()
            raise HTTPException(status_code=401, detail="Invalid login or password")
        db.delete(attempt) if attempt is not None else None
        _audit(db, user.id, "login_success", "user", user.id)
        db.commit()
        return make_tokens(user)

    @app.get("/api/v1/me")
    def me(user: Annotated[User, Depends(current_user)]):
        return _user_json(user)

    @app.get("/api/v1/classes")
    def classes(user: Annotated[User, Depends(current_user)], db: Annotated[Session, Depends(get_db)]):
        if user.role == "admin":
            items = list(db.scalars(select(SchoolClass).order_by(SchoolClass.name)))
        elif user.role == "teacher":
            items = list(db.scalars(select(SchoolClass).join(
                TeacherAssignment, TeacherAssignment.class_id == SchoolClass.id
            ).where(TeacherAssignment.teacher_id == user.id).order_by(SchoolClass.name)))
        elif user.role == "student":
            items = list(db.scalars(select(SchoolClass).join(
                ClassMembership, ClassMembership.class_id == SchoolClass.id
            ).where(ClassMembership.student_id == user.id)))
        else:
            linked_ids = select(ClassMembership.class_id).where(
                ClassMembership.student_id.in_(select(MentorAssignment.student_id).where(MentorAssignment.mentor_id == user.id))
            )
            items = list(db.scalars(select(SchoolClass).where(SchoolClass.id.in_(linked_ids))))
        return {"data": [_class_json(item) for item in items]}


    @app.get("/api/v1/classes/{class_id}/schedule")
    def class_schedule(class_id: str, user: Annotated[User, Depends(current_user)],
                       db: Annotated[Session, Depends(get_db)]):
        if not _can_view_class(db, user, class_id):
            raise HTTPException(status_code=403, detail="You cannot view this class schedule")
        data = db.scalars(select(ScheduleRecord).where(
            ScheduleRecord.class_id == class_id
        ).order_by(ScheduleRecord.weekday, ScheduleRecord.lesson_number)).all()
        return {"data": [_schedule_json(item) for item in data]}

    @app.get("/api/v1/students")
    def students(user: Annotated[User, Depends(current_user)], db: Annotated[Session, Depends(get_db)],
                 class_id: str | None = None):
        if user.role == "admin":
            query = select(User).where(User.role == "student", User.active.is_(True))
        elif user.role == "mentor":
            query = select(User).join(MentorAssignment, MentorAssignment.student_id == User.id).where(
                MentorAssignment.mentor_id == user.id, User.active.is_(True))
        elif user.role == "teacher":
            class_ids = select(TeacherAssignment.class_id).where(TeacherAssignment.teacher_id == user.id)
            query = select(User).join(ClassMembership, ClassMembership.student_id == User.id).where(
                ClassMembership.class_id.in_(class_ids), User.active.is_(True))
        elif user.role == "student":
            query = select(User).where(User.id == user.id)
        else:
            query = select(User).where(User.id == "__no_students__")
        if class_id:
            query = query.join(ClassMembership, ClassMembership.student_id == User.id).where(ClassMembership.class_id == class_id)
            if user.role == "teacher":
                assigned = select(TeacherAssignment.class_id).where(TeacherAssignment.teacher_id == user.id)
                if class_id not in set(db.scalars(assigned)):
                    raise HTTPException(status_code=403, detail="Class is not assigned to this teacher")
        found = list(db.scalars(query.distinct().order_by(User.display_name)))
        return {"data": [_user_json(item) for item in found]}

    @app.post("/api/v1/admin/users", status_code=status.HTTP_201_CREATED)
    def create_user(body: UserCreate, actor: Annotated[User, Depends(require_roles("admin"))],
                    db: Annotated[Session, Depends(get_db)]):
        user = User(login=body.login.strip().casefold(), display_name=body.display_name.strip(), role=body.role,
                    password_hash=ph.hash(body.password), active=body.active)
        db.add(user)
        try:
            db.flush()
            _audit(db, actor.id, "user_created", "user", user.id, {"role": user.role})
            db.commit()
            db.refresh(user)
        except IntegrityError:
            db.rollback()
            raise HTTPException(status_code=409, detail="Login already exists")
        return _user_json(user)


    @app.get("/api/v1/admin/users")
    def list_users(actor: Annotated[User, Depends(require_roles("admin"))],
                   db: Annotated[Session, Depends(get_db)]):
        rows = db.scalars(select(User).order_by(User.role, User.display_name)).all()
        return {"data": [_user_json(item) for item in rows]}

    @app.patch("/api/v1/admin/users/{user_id}")
    def update_user(user_id: str, body: UserUpdate,
                    actor: Annotated[User, Depends(require_roles("admin"))],
                    db: Annotated[Session, Depends(get_db)]):
        item = db.get(User, user_id)
        if item is None:
            raise HTTPException(status_code=404, detail="User not found")
        changes = body.model_dump(exclude_unset=True)
        next_role = changes.get("role", item.role)
        next_active = changes.get("active", item.active)
        if item.id == actor.id and (next_role != "admin" or not next_active):
            raise HTTPException(status_code=409, detail="Do not disable or demote your own administrator account")
        if item.role == "admin" and item.active and (next_role != "admin" or not next_active):
            another_admin = db.scalar(select(User.id).where(
                User.role == "admin", User.active.is_(True), User.id != item.id
            ).limit(1))
            if another_admin is None:
                raise HTTPException(status_code=409, detail="At least one active administrator must remain")
        if "display_name" in changes and changes["display_name"] is not None:
            changes["display_name"] = changes["display_name"].strip()
            if not changes["display_name"]:
                raise HTTPException(status_code=422, detail="Display name cannot be empty")
        password = changes.pop("password", None)
        for key, value in changes.items():
            if value is not None:
                setattr(item, key, value)
        if password:
            item.password_hash = ph.hash(password)
        _audit(db, actor.id, "user_updated", "user", item.id,
               {"changed_fields": sorted(changes.keys() | ({"password"} if password else set()))})
        db.commit()
        db.refresh(item)
        return _user_json(item)

    @app.post("/api/v1/admin/classes", status_code=status.HTTP_201_CREATED)
    def create_class(body: ClassCreate, actor: Annotated[User, Depends(require_roles("admin"))],
                     db: Annotated[Session, Depends(get_db)]):
        item = SchoolClass(id=body.id.strip(), name=body.name.strip(), grade=body.grade.strip())
        db.add(item)
        try:
            db.flush()
            _audit(db, actor.id, "class_created", "class", item.id)
            db.commit()
        except IntegrityError:
            db.rollback()
            raise HTTPException(status_code=409, detail="Class id or name already exists")
        return _class_json(item)

    @app.post("/api/v1/admin/assignments/mentor", status_code=status.HTTP_201_CREATED)
    def assign_mentor(body: MentorLinkBody, actor: Annotated[User, Depends(require_roles("admin"))],
                      db: Annotated[Session, Depends(get_db)]):
        mentor = db.get(User, body.mentor_id)
        student = db.get(User, body.student_id)
        if mentor is None or mentor.role != "mentor" or student is None or student.role != "student":
            raise HTTPException(status_code=422, detail="Assignment requires a mentor and a student account")
        link = MentorAssignment(mentor_id=mentor.id, student_id=student.id)
        db.add(link)
        try:
            db.flush()
            _audit(db, actor.id, "mentor_assigned", "student", student.id, {"mentor_id": mentor.id})
            db.commit()
        except IntegrityError:
            db.rollback()
            raise HTTPException(status_code=409, detail="Assignment already exists")
        return {"mentor_id": mentor.id, "student_id": student.id}

    @app.post("/api/v1/admin/assignments/teacher", status_code=status.HTTP_201_CREATED)
    def assign_teacher(body: TeacherLinkBody, actor: Annotated[User, Depends(require_roles("admin"))],
                       db: Annotated[Session, Depends(get_db)]):
        teacher = db.get(User, body.teacher_id)
        if teacher is None or teacher.role != "teacher" or db.get(SchoolClass, body.class_id) is None:
            raise HTTPException(status_code=422, detail="Assignment requires a teacher and an existing class")
        link = TeacherAssignment(teacher_id=teacher.id, class_id=body.class_id)
        db.add(link)
        try:
            db.flush()
            _audit(db, actor.id, "teacher_assigned", "class", body.class_id, {"teacher_id": teacher.id})
            db.commit()
        except IntegrityError:
            db.rollback()
            raise HTTPException(status_code=409, detail="Assignment already exists")
        return {"teacher_id": teacher.id, "class_id": body.class_id}

    @app.post("/api/v1/admin/class-memberships", status_code=status.HTTP_201_CREATED)
    def add_class_membership(body: ClassMembershipBody, actor: Annotated[User, Depends(require_roles("admin"))],
                             db: Annotated[Session, Depends(get_db)]):
        student = db.get(User, body.student_id)
        if student is None or student.role != "student" or db.get(SchoolClass, body.class_id) is None:
            raise HTTPException(status_code=422, detail="Membership requires a student and an existing class")
        link = ClassMembership(student_id=student.id, class_id=body.class_id)
        db.add(link)
        try:
            db.flush()
            _audit(db, actor.id, "student_added_to_class", "student", student.id, {"class_id": body.class_id})
            db.commit()
        except IntegrityError:
            db.rollback()
            raise HTTPException(status_code=409, detail="Student is already in this class")
        return {"student_id": student.id, "class_id": body.class_id}

    @app.post("/api/v1/admin/schedule", status_code=status.HTTP_201_CREATED)
    def add_schedule(body: ScheduleBody, actor: Annotated[User, Depends(require_roles("admin"))],
                     db: Annotated[Session, Depends(get_db)]):
        if db.get(SchoolClass, body.class_id) is None:
            raise HTTPException(status_code=422, detail="Unknown class")
        item = ScheduleRecord(**body.model_dump())
        db.add(item)
        _audit(db, actor.id, "schedule_created", "schedule", item.id, {"class_id": item.class_id})
        db.commit()
        db.refresh(item)
        return _schedule_json(item)


    @app.patch("/api/v1/admin/schedule/{record_id}")
    def update_schedule(record_id: str, body: ScheduleUpdate,
                       actor: Annotated[User, Depends(require_roles("admin"))],
                       db: Annotated[Session, Depends(get_db)]):
        item = db.get(ScheduleRecord, record_id)
        if item is None:
            raise HTTPException(status_code=404, detail="Schedule record not found")
        changes = {k: v for k, v in body.model_dump(exclude_unset=True).items() if v is not None}
        if "class_id" in changes and db.get(SchoolClass, changes["class_id"]) is None:
            raise HTTPException(status_code=422, detail="Unknown class")
        if "subject" in changes:
            changes["subject"] = changes["subject"].strip()
            if not changes["subject"]:
                raise HTTPException(status_code=422, detail="Subject cannot be empty")
        for key, value in changes.items():
            setattr(item, key, value)
        item.updated_at = utcnow()
        _audit(db, actor.id, "schedule_updated", "schedule", item.id,
               {"changed_fields": sorted(changes.keys())})
        db.commit()
        db.refresh(item)
        return _schedule_json(item)

    @app.delete("/api/v1/admin/schedule/{record_id}", status_code=status.HTTP_204_NO_CONTENT)
    def delete_schedule(record_id: str, actor: Annotated[User, Depends(require_roles("admin"))],
                        db: Annotated[Session, Depends(get_db)]):
        item = db.get(ScheduleRecord, record_id)
        if item is None:
            raise HTTPException(status_code=404, detail="Schedule record not found")
        _audit(db, actor.id, "schedule_deleted", "schedule", item.id, {"class_id": item.class_id})
        db.delete(item)
        db.commit()
        return Response(status_code=status.HTTP_204_NO_CONTENT)

    @app.post("/api/v1/admin/supplements", status_code=status.HTTP_201_CREATED)
    def add_supplement(body: SupplementBody, actor: Annotated[User, Depends(require_roles("admin"))],
                       db: Annotated[Session, Depends(get_db)]):
        student = db.get(User, body.student_id)
        if student is None or student.role != "student":
            raise HTTPException(status_code=422, detail="Supplement must be attached to a student")
        item = SupplementRecord(**body.model_dump())
        db.add(item)
        _audit(db, actor.id, "supplement_created", "supplement", item.id, {"student_id": item.student_id})
        db.commit()
        db.refresh(item)
        return _supplement_json(item)


    @app.patch("/api/v1/admin/supplements/{record_id}")
    def update_supplement(record_id: str, body: SupplementUpdate,
                          actor: Annotated[User, Depends(require_roles("admin"))],
                          db: Annotated[Session, Depends(get_db)]):
        item = db.get(SupplementRecord, record_id)
        if item is None:
            raise HTTPException(status_code=404, detail="Supplement record not found")
        changes = {k: v for k, v in body.model_dump(exclude_unset=True).items() if v is not None}
        if "student_id" in changes:
            student = db.get(User, changes["student_id"])
            if student is None or student.role != "student":
                raise HTTPException(status_code=422, detail="Supplement must be attached to a student")
        if "title" in changes:
            changes["title"] = changes["title"].strip()
            if not changes["title"]:
                raise HTTPException(status_code=422, detail="Supplement title cannot be empty")
        for key, value in changes.items():
            setattr(item, key, value)
        item.updated_at = utcnow()
        _audit(db, actor.id, "supplement_updated", "supplement", item.id,
               {"changed_fields": sorted(changes.keys())})
        db.commit()
        db.refresh(item)
        return _supplement_json(item)

    @app.delete("/api/v1/admin/supplements/{record_id}", status_code=status.HTTP_204_NO_CONTENT)
    def delete_supplement(record_id: str, actor: Annotated[User, Depends(require_roles("admin"))],
                          db: Annotated[Session, Depends(get_db)]):
        item = db.get(SupplementRecord, record_id)
        if item is None:
            raise HTTPException(status_code=404, detail="Supplement record not found")
        _audit(db, actor.id, "supplement_deleted", "supplement", item.id,
               {"student_id": item.student_id})
        db.delete(item)
        db.commit()
        return Response(status_code=status.HTTP_204_NO_CONTENT)

    @app.get("/api/v1/students/{student_id}/supplements")
    def student_supplements(student_id: str, user: Annotated[User, Depends(current_user)],
                            db: Annotated[Session, Depends(get_db)]):
        if not _can_view_student(db, user, student_id):
            raise HTTPException(status_code=403, detail="You cannot view this student's records")
        data = db.scalars(select(SupplementRecord).where(
            SupplementRecord.student_id == student_id
        ).order_by(SupplementRecord.weekday, SupplementRecord.start_time))
        return {"data": [_supplement_json(item) for item in data]}

    @app.get("/api/v1/students/{student_id}/schedule")
    def student_schedule(student_id: str, user: Annotated[User, Depends(current_user)],
                         db: Annotated[Session, Depends(get_db)]):
        if not _can_view_student(db, user, student_id):
            raise HTTPException(status_code=403, detail="You cannot view this student's records")
        class_ids = list(db.scalars(select(ClassMembership.class_id).where(ClassMembership.student_id == student_id)))
        if not class_ids:
            return {"data": []}
        data = db.scalars(select(ScheduleRecord).where(
            ScheduleRecord.class_id.in_(class_ids)
        ).order_by(ScheduleRecord.weekday, ScheduleRecord.lesson_number))
        return {"data": [_schedule_json(item) for item in data]}

    @app.get("/api/v1/mentees")
    def mentees(user: Annotated[User, Depends(require_roles("mentor", "admin"))],
                db: Annotated[Session, Depends(get_db)]):
        if user.role == "admin":
            rows = db.scalars(select(User).where(User.role == "student", User.active.is_(True))).all()
        else:
            rows = db.scalars(select(User).join(
                MentorAssignment, MentorAssignment.student_id == User.id
            ).where(MentorAssignment.mentor_id == user.id, User.active.is_(True))).all()
        result = []
        for student in rows:
            supplements = db.scalars(select(SupplementRecord).where(
                SupplementRecord.student_id == student.id
            ).order_by(SupplementRecord.weekday, SupplementRecord.start_time)).all()
            classes_for_student = list(db.scalars(select(SchoolClass).join(
                ClassMembership, ClassMembership.class_id == SchoolClass.id
            ).where(ClassMembership.student_id == student.id)))
            result.append({
                "student": _user_json(student),
                "classes": [_class_json(c) for c in classes_for_student],
                "supplements": [_supplement_json(s) for s in supplements],
            })
        return {"data": result}

    @app.post("/api/v1/devices/register", status_code=status.HTTP_201_CREATED)
    def register_device(body: DeviceBody, user: Annotated[User, Depends(current_user)],
                        db: Annotated[Session, Depends(get_db)]):
        existing = db.scalar(select(Device).where(Device.token == body.token).limit(1))
        if existing is not None:
            existing.user_id = user.id
            existing.platform = body.platform
            existing.active = True
            existing.updated_at = utcnow()
            item = existing
        else:
            item = Device(user_id=user.id, token=body.token, platform=body.platform, active=True)
            db.add(item)
        _audit(db, user.id, "push_device_registered", "device", item.id, {"platform": body.platform})
        db.commit()
        db.refresh(item)
        return {"id": item.id, "registered": True}

    @app.delete("/api/v1/devices/{device_id}", status_code=status.HTTP_204_NO_CONTENT)
    def unregister_device(device_id: str, user: Annotated[User, Depends(current_user)],
                          db: Annotated[Session, Depends(get_db)]):
        item = db.get(Device, device_id)
        if item is None:
            return Response(status_code=status.HTTP_204_NO_CONTENT)
        if item.user_id != user.id and user.role != "admin":
            raise HTTPException(status_code=403, detail="You cannot unregister this device")
        db.delete(item)
        _audit(db, user.id, "push_device_unregistered", "device", device_id)
        db.commit()
        return Response(status_code=status.HTTP_204_NO_CONTENT)

    @app.get("/api/v1/alerts")
    def get_alerts(user: Annotated[User, Depends(current_user)], db: Annotated[Session, Depends(get_db)],
                   limit: int = 50):
        if user.role not in ROLES:
            raise HTTPException(status_code=403, detail="Insufficient permissions")
        limit = max(1, min(limit, 100))
        candidates = db.scalars(select(AlertRecord).order_by(AlertRecord.created_at.desc()).limit(300)).all()
        return {"data": [_alert_json(a) for a in candidates if _alert_visible(db, user, a)][:limit]}

    @app.post("/api/v1/alerts", status_code=status.HTTP_201_CREATED)
    def create_alert(body: AlertBody, actor: Annotated[User, Depends(require_roles("admin", "emergency_manager"))],
                     db: Annotated[Session, Depends(get_db)]):
        if body.target_type == "role" and body.target_value not in ROLES:
            raise HTTPException(status_code=422, detail="Unknown role audience")
        if body.target_type == "class" and db.get(SchoolClass, body.target_value) is None:
            raise HTTPException(status_code=422, detail="Unknown class audience")
        if body.target_type == "user":
            target = db.get(User, body.target_value)
            if target is None:
                raise HTTPException(status_code=422, detail="Unknown user audience")
        item = AlertRecord(
            title=body.title.strip(), body=body.body.strip(), severity=body.severity,
            target_type=body.target_type, target_value=body.target_value.strip(),
            sender_id=actor.id, fcm_status="pending",
        )
        db.add(item)
        db.flush()
        _audit(db, actor.id, "school_alert_created", "alert", item.id,
               {"severity": item.severity, "target_type": item.target_type})
        db.commit()
        db.refresh(item)

        recipient_ids = _target_user_ids(db, item)
        token_rows = db.scalars(select(Device.token).where(
            Device.user_id.in_(recipient_ids) if recipient_ids else Device.user_id == "__no_matching_users__",
            Device.active.is_(True),
        )).all()
        provider_status, sent, failed = _send_fcm(app.state.firebase_app, list(token_rows), item)
        item.fcm_status = provider_status
        db.commit()
        return {**_alert_json(item), "delivery": {"status": provider_status, "sent": sent, "failed": failed}}

    @app.get("/api/v1/admin/audit")
    def audit_events(actor: Annotated[User, Depends(require_roles("admin"))],
                     db: Annotated[Session, Depends(get_db)], limit: int = 100):
        limit = max(1, min(limit, 300))
        rows = db.scalars(select(AuditEvent).order_by(AuditEvent.created_at.desc()).limit(limit)).all()
        return {"data": [{
            "id": e.id, "actor_id": e.actor_id, "action": e.action, "target_type": e.target_type,
            "target_id": e.target_id, "details": json.loads(e.details_json),
            "created_at": e.created_at.isoformat(),
        } for e in rows]}

    @app.on_event("shutdown")
    def shutdown():
        engine.dispose()

    return app


app = create_app()
