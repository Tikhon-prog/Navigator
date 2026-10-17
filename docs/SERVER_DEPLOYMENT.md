# Navigator School API — deployment and hand-off

## What is implemented

**backend/server_app.py** is a separate role-based API; it does not replace the existing read-only **backend/main.py** workbook API yet.

- PostgreSQL-ready persistence (SQLAlchemy); SQLite is the development default.
- Bootstrap key for the first administrator; Argon2 password hashes; short-lived signed JWT access tokens.
- Persistent failed-login counters and temporary lockouts.
- Roles: **admin**, **mentor**, **teacher**, **student**, **emergency_manager**.
- Explicit mentor→student, teacher→class and student→class assignments.
- Server-side authorization for student records, class schedules and supplements.
- Administrative audit events for account, assignment, schedule, supplement, device and alert changes.
- School alerts targeted to everyone, a role, a class or one user.
- Optional Firebase Admin SDK delivery to registered devices. Without Firebase credentials, alerts are still saved and readable from the authenticated **/api/v1/alerts** inbox; the response reports **not_configured**.

## Local development

From the repository root:

~~~powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r backend/requirements.txt
$env:NAVIGATOR_JWT_SECRET = python -c "import secrets; print(secrets.token_urlsafe(48))"
$env:BOOTSTRAP_ADMIN_KEY = python -c "import secrets; print(secrets.token_urlsafe(32))"
python -m uvicorn backend.server_app:app --host 127.0.0.1 --port 8000
~~~

The first administrator is created once with **POST /api/v1/auth/bootstrap**. Use the bootstrap key in the request body. After the first administrator exists, the endpoint returns **409**; keep the bootstrap key outside the app and rotate/remove it after setup.

For a quick health check, request **GET /api/v1/health**. API documentation is available at **/docs** in development.

## Production host setup

1. Provision a managed PostgreSQL database and a dedicated database user with only the required privileges. Set **DATABASE_URL** to a TLS-enabled PostgreSQL connection string. Keep **APP_ENV=production**.
2. Generate a unique random **NAVIGATOR_JWT_SECRET** of at least 32 characters and a separate **BOOTSTRAP_ADMIN_KEY**. Store them only in the hosting provider's secret manager.
3. Configure **FIREBASE_SERVICE_ACCOUNT_JSON** as a secret containing the service account JSON if push notifications are approved. Never place this JSON, OAuth tokens, private keys, the database password or similar secrets in Flutter assets, Git, build logs or APK files.
4. Run behind a managed HTTPS ingress/reverse proxy. Do not expose a plain HTTP API to the public internet. Restrict database network access to the app service, configure backups and test restore.
5. Create the initial admin, then remove/rotate the bootstrap key. Add school accounts and assignments through the admin API or a reviewed import job.
6. Set monitoring and alerts for repeated login failures, HTTP 5xx errors, database availability and Firebase delivery failures. Define database retention and staff offboarding procedures with the school.

The service intentionally refuses to start in production without **NAVIGATOR_JWT_SECRET**. Do not launch multiple workers against SQLite in production; use PostgreSQL.

## API contracts

All endpoints except **/**, **/api/v1/health**, **/api/v1/auth/bootstrap** and **/api/v1/auth/login** require an **Authorization: Bearer <access_token>** header.

| Endpoint | Access / purpose |
|---|---|
| POST /api/v1/auth/bootstrap | One-time first admin setup; requires out-of-band bootstrap key |
| POST /api/v1/auth/login, GET /api/v1/me | Login and current identity |
| GET /api/v1/classes, GET /api/v1/students | Only classes/students visible to the current role |
| GET /api/v1/classes/{id}/schedule | Schedule for an authorised class; checked against class/mentor assignments |
| GET /api/v1/admin/users, POST /api/v1/admin/users, PATCH /api/v1/admin/users/{id} | Admin account listing, creation and update; prevents disabling/demoting the last active admin |
| POST /api/v1/admin/classes | Admin creates a class |
| POST /api/v1/admin/assignments/mentor | Admin links a mentor to a student |
| POST /api/v1/admin/assignments/teacher | Admin links a teacher to a class |
| POST /api/v1/admin/class-memberships | Admin links a student to a class |
| POST/PATCH/DELETE /api/v1/admin/schedule[/{id}] | Admin creates, edits and deletes schedule records |
| POST/PATCH/DELETE /api/v1/admin/supplements[/{id}] | Admin creates, edits and deletes student DOP records |
| GET /api/v1/mentees | Mentor sees only assigned students, their classes, class schedules and supplements |
| GET /api/v1/students/{id}/schedule | Own student schedule; mentor/teacher only for assigned students/classes; admin for any student |
| GET /api/v1/students/{id}/supplements | Same access policy for the student's additional activities |
| POST /api/v1/devices/register, DELETE /api/v1/devices/{id} | Register/revoke the signed-in user's push device |
| POST /api/v1/alerts, GET /api/v1/alerts | School alert creation (admin/emergency manager) and personal inbox |
| GET /api/v1/admin/audit | Admin-only audit trail |

The API uses explicit IDs as a transport contract; production SSO/account provisioning and the school's authoritative class/mentor assignments still need to be agreed and connected. Do not let clients choose their own role or relationship: those values are created only through admin routes.

## Firebase client integration

**lib/push_notification_service.dart** is an optional adapter. It should be initialized only after the school authentication flow has issued a valid API access token, with the FirebaseOptions generated for the school's Firebase project. The current app does not yet have school SSO, so do not call this service from app startup with a fake identity or placeholder token.

Before enabling push:
- Create a Firebase project owned/approved by the school; enable Cloud Messaging and add the actual Android/iOS apps.
- Generate platform configuration using FlutterFire tooling and pass the generated FirebaseOptions; never invent or commit service-account credentials.
- Verify permission prompts, token refresh, logout/device revocation, foreground presentation, notification taps and delivery on physical devices.
- Use generic lock-screen text for sensitive situations. For a critical evacuation alert, include clear actionable instructions and use the school's emergency procedure as the source of truth. This app is supplemental; it must not replace the school sound system, staff instruction or official emergency protocol.

## Important release gates

This is an implementation scaffold, not an approved school production deployment. Before real student data is loaded, the school must approve the identity provider/SSO, authoritative source of class membership and mentor relationships, data retention, emergency-alert privileges, hosting region, privacy notice and incident-response owner. Conduct a security review, restore test, load test and end-to-end push drill first.

The older **backend/main.py** Excel/Yandex Disk API remains separate. A reviewed migration/import process is needed before treating the new PostgreSQL data as the school's source of truth. Review and rotate any previously exposed Yandex OAuth token described in **docs/SECURITY.md**.
