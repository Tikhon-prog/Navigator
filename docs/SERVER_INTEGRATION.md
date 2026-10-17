# Navigator school server integration

This branch adds a first usable, separately versioned service API at `/api/v2`.
The existing workbook-backed `/api/*` endpoints remain read-only and unchanged.
The new service stores identities, mentor/teacher relationships, student-specific
supplements, registered devices, announcements, and audit events in SQLite.

## Roles and visibility

- `admin`: creates accounts and student/staff relationships, adds student supplement
  records, publishes announcements, and reads the audit log.
- `mentor`: can list and inspect only students explicitly linked to that mentor,
  including their supplement records.
- `teacher`: can inspect only students explicitly linked to them, with a subject label
  recorded on each assignment. Use `GET /api/v2/teachers/me/subjects` for the subject roster.
- `student`: can inspect only their own record (the public endpoint is intentionally
  narrower than staff access).

Do not infer mentor relationships from names or class labels. The school must provide
an authoritative mapping and a responsible administrator must import or approve it.

## Environment

Required for authenticated endpoints:
- `NAVIGATOR_TOKEN_SECRET`: random secret, at least 32 characters; keep it outside Git.
- `NAVIGATOR_DB_PATH`: writable persistent path for the SQLite database (default is
  `backend/navigator.sqlite3`, suitable for development, not ephemeral production containers).
- `NAVIGATOR_BOOTSTRAP_ADMIN_USERNAME` and `NAVIGATOR_BOOTSTRAP_ADMIN_PASSWORD`:
  optional initial admin account; password must be at least 14 characters. The bootstrap
  account is created only when there is no existing admin.
- `NAVIGATOR_TOKEN_TTL_SECONDS`: access token lifetime, default 8 hours.
- `FIREBASE_CREDENTIALS_PATH`: path to a Firebase service-account JSON file mounted
  as a secret, never committed to the repository.

Install base dependencies with `pip install -r backend/requirements.txt`.
For push delivery additionally run `pip install -r backend/requirements-firebase.txt`.
Mount credentials read-only and create an FCM-enabled Firebase project first.

## Routes

- `POST /api/v2/auth/login` — username/password to bearer token.
- `GET /api/v2/auth/me` — current account.
- `POST /api/v2/admin/users` — create an account.
- `POST /api/v2/admin/student-links` — explicitly associate a student with a mentor/teacher; include `subject` for teacher assignments.
- `GET /api/v2/teachers/me/subjects` — list students explicitly assigned to the signed-in teacher by subject.
- `GET /api/v2/students` and `GET /api/v2/students/{id}` — role-scoped student list/details.
- `POST /api/v2/admin/students/{id}/supplements` — add a student-specific supplement record.
- `POST /api/v2/devices/register` — register an FCM device token for the signed-in user.
- `GET /api/v2/announcements` — list announcements visible to the current user.
- `POST /api/v2/admin/announcements` — publish info, warning, or emergency notice.
- `GET /api/v2/admin/audit` — inspect recent audit events.

Use the header `Authorization: Bearer <access_token>` on authenticated requests.
Example login body: `{"username":"admin","password":"<secret>"}`.
Example emergency notice body:
`{"title":"Учебная тревога","body":"Следуйте указаниям сотрудников школы.","severity":"emergency","audience":"all"}`.

## Emergency-notification limitations

The API sends a Firebase Cloud Messaging notification when Firebase is configured and
valid device tokens exist. It does not trigger or replace the school's PA/loudspeaker
system, fire-alarm hardware, 112, or any official emergency process. Push delivery is
best-effort; mobile OS settings, network coverage, battery restrictions, and provider
latency can delay or suppress it. Never rely on the app as the only alarm channel.
Use short, pre-approved templates and let school leadership authorize emergency
broadcasts. Do not include sensitive student information in global messages.

## Production hardening required before real student data

This is a functional integration scaffold, not yet an approved production deployment.
Before using real student data: deploy only behind HTTPS; configure secrets through the
hosting secret manager; use a persistent encrypted database with backups and retention
rules; enable centralized rate limiting; add account recovery/deactivation workflows;
review local privacy/legal requirements with school leadership; test database migration
and restore; decide how Firebase tokens are revoked; and replace SQLite with PostgreSQL
if multiple app instances or higher write concurrency are needed. The current login
throttle is process-local and is not a substitute for edge rate limiting. Teacher visibility
is deliberately based on explicit subject assignments, not inferred from a shared class.


## School SSO

The server now exposes `POST /api/v2/auth/sso`. The Android app should use the school's
OIDC Authorization Code flow with PKCE through the official school identity provider,
then send the resulting short-lived access token to this endpoint. Configure:

- `NAVIGATOR_OIDC_ISSUER`: canonical issuer URL from the school identity provider.
- `NAVIGATOR_OIDC_USERINFO_URL`: that provider's HTTPS UserInfo endpoint.

The server calls UserInfo over TLS and uses the returned stable `sub` claim. It **does
not auto-link by email or username**. An administrator must explicitly link a local
Navigator account once using `POST /api/v2/admin/sso-identities` with
`{"username":"existing-login","subject":"stable-oidc-subject"}`. This avoids
account takeover through mismatched or unverified profile claims. Do not enable this
until the school IT team supplies and approves the issuer/endpoints and mobile client
registration. The legacy password login remains for local development/admin bootstrap,
not as the assumed student login experience.

## Multiple school-data sources

Set `NAVIGATOR_DATA_SOURCE` to one of:

- `yandex` (default): existing workbook and `YANDEX_OAUTH_TOKEN` flow.
- `json`: read the allowlisted sheet names from `NAVIGATOR_DATA_JSON_PATH`, a local
  UTF-8 JSON object whose values are arrays of row objects.
- `http`: request `{NAVIGATOR_DATA_API_URL}/{SheetName}`; the endpoint may return
  either a JSON array or an object with a `data` array. Optional bearer token:
  `NAVIGATOR_DATA_API_TOKEN`.

The current HTTP/JSON adapters cover the existing read-only sheet endpoints. Identity,
relationships, personal notifications, and device tokens remain in the service database
until a school-approved import/synchronization adapter is implemented. Keep the source
token on the server; never put it in the APK. Use HTTPS for remote endpoints.

## Scoped notifications and DOP reminders

- `POST /api/v2/admin/notifications` supports `global`, `targeted`, `personal`,
  `dop_reminder`, and `emergency` kinds; targets can be all users, a class, a group,
  or a single user. Only admins can publish emergency items.
- `POST /api/v2/admin/notification-groups` creates a target group.
- `POST /api/v2/admin/notification-groups/{group_id}/members` adds an active account.
- `GET /api/v2/notifications` returns only notifications visible to the signed-in user.
- `scheduled_at` is stored and hides a notification until its due time. It is **not yet
  a delivery scheduler**: a worker must be deployed to send due push notifications. This
  API does not claim a scheduled reminder has been delivered.
- These new notification records are not yet wired to FCM delivery. Existing broadcast
  announcements can send FCM pushes when configured; per-user/group push fan-out and
  delivery receipts remain follow-up work.


## Portable deployment

A Dockerfile and `docker-compose.yml` are included. Copy `.env.example` to `.env`,
fill in the values supplied by school IT, then run `docker compose up --build -d`.
The SQLite database persists in the `navigator_data` volume. Back it up and restrict
host access. This only packages the API; it does not provision school SSO, Firebase,
Yandex access, certificates, or official school data. Do not expose port 8000 directly
to the public internet; put it behind the school's HTTPS reverse proxy.
