# Серверная интеграция школы «Поколение»

This branch adds a first usable, separately versioned service API at `/api/v2`.
The existing workbook-backed `/api/*` endpoints remain read-only and unchanged.
The new service stores identities, mentor/teacher relationships, student-specific
supplements, registered devices, announcements, and audit events in SQLite.

## Roles and visibility

The base account type is separate from a school position. Positions are stored and granted
by an existing administrator; they do not automatically turn a teacher into a superadmin.

- `admin`: technical administrator; provisions accounts, links SSO identities, grants positions, and can audit the system.
- `director`: school-wide management dashboard, student directory, DOP oversight, account lifecycle, assignments, notifications and audit read access.
- `deputy`: school-wide academic/operational overview, DOP oversight, staff lifecycle, assignments, notifications and audit read access; cannot grant director/deputy or create another superadmin.
- `homeroom_teacher`: student roster and DOP view limited to the explicitly assigned class; class and personal messages only to students in that class.
- `teacher`: students explicitly assigned by subject; personal messages only to assigned students; student detail responses do not disclose the full private DOP schedule.
- `mentor`: only explicitly linked mentees, including their relevant DOP records.
- `mentor_coordinator`: school student directory for assignment purposes and authority to manage mentor/subject assignments.
- `dop_coordinator`: student directory, DOP import/CRUD, class-targeted notifications, and opted-in server DOP reminder oversight.
- `librarian`: read-only student directory; no private DOP access by default.
- `student`: only their own profile, assigned DOP records and notifications addressed to them/their class.

A single account has one optional position and one optional class scope. Teacher-subject
assignments and mentor relationships are explicit database records. Do not infer them from
names, emails or class labels; the school must provide an authoritative mapping and an
administrator must import or approve it.

## Environment

Required for authenticated endpoints:
- `NAVIGATOR_TOKEN_SECRET`: random secret, at least 32 characters; keep it outside Git.
  Generate one with `python -c "import secrets; print(secrets.token_urlsafe(48))"` on the server.
- `NAVIGATOR_DB_PATH`: writable persistent path for the SQLite database (default is
  `backend/navigator.sqlite3`, suitable for development, not ephemeral production containers).
- `NAVIGATOR_BOOTSTRAP_ADMIN_USERNAME` and `NAVIGATOR_BOOTSTRAP_ADMIN_PASSWORD`:
  initial technical admin account; password must be at least 14 characters. The bootstrap
  account is created only when there is no existing admin. Use this account for the first
  technical login, then link the school's SSO identities or enable trusted-claim provisioning.
- `NAVIGATOR_TOKEN_TTL_SECONDS`: access token lifetime, default 8 hours.
- `NAVIGATOR_REFRESH_TTL_SECONDS`: rotating refresh-token lifetime, default 30 days.
- `NAVIGATOR_NOTIFICATION_WORKER_ENABLED` and `NAVIGATOR_NOTIFICATION_POLL_SECONDS`: enable and tune the single-container notification worker.
- `NAVIGATOR_AUTO_SYNC_INTERVAL_SECONDS`: automatically refresh student DOPs and timetable-derived teacher assignments; set `0` to disable periodic sync. The default is 300 seconds.
- `NAVIGATOR_SCHOOL_TIMEZONE`: timezone used for server-generated DOP reminders (default `Europe/Moscow`).
- `NAVIGATOR_ALLOWED_ORIGINS`: comma-separated browser origins allowed by CORS; set the real school portal origin in production.
- `NAVIGATOR_OIDC_ISSUER`, `NAVIGATOR_OIDC_USERINFO_URL`, `NAVIGATOR_OIDC_CLIENT_ID` and `NAVIGATOR_OIDC_REDIRECT_URI`: values registered by school IT. The redirect URI must match the Android intent filter and the identity-provider registration.
- `NAVIGATOR_OIDC_AUTO_LINK_USERNAME` and `NAVIGATOR_OIDC_AUTO_PROVISION`: optional first-login automation. Enable only if the configured IdP returns authoritative, non-user-editable username/role/class claims. Configure the claim names explicitly; student accounts require a class claim. Provisioning of `admin` accounts stays disabled unless `NAVIGATOR_OIDC_ALLOW_ADMIN_PROVISION=true`.
- `NAVIGATOR_DATA_SOURCE`: `yandex`, `json` or `http`; the selected source must expose compatible `Classes` and `BaseSchedule` rows.
- `NAVIGATOR_ENABLE_FIREBASE`, the four `FIREBASE_*` public app settings and one server credential source: required for end-to-end FCM.
- `FIREBASE_CREDENTIALS_PATH`: optional path to a Firebase service-account JSON file mounted
  read-only as a secret, never committed to the repository. Alternatively, set
  `FIREBASE_CREDENTIALS_JSON_BASE64` to the one-line Base64 encoding of that JSON. Protect
  `.env` with restrictive filesystem permissions; never put real credentials in Git.

Install base dependencies with `pip install -r backend/requirements.txt`.
For push delivery additionally run `pip install -r backend/requirements-firebase.txt`.
Create an FCM-enabled Firebase project first. For the one-line environment option, generate the value with `base64 -w0 service-account.json` on Linux or `[Convert]::ToBase64String([IO.File]::ReadAllBytes('service-account.json'))` in PowerShell. The Android app also needs the public Firebase Android app settings (`FIREBASE_WEB_API_KEY`, `FIREBASE_ANDROID_APP_ID`, `FIREBASE_MESSAGING_SENDER_ID`, `FIREBASE_PROJECT_ID`) so it can initialize Firebase at runtime.

## Routes

- `POST /api/v2/auth/login` — local username/password session.
- `POST /api/v2/auth/sso` — exchange the school OIDC access token for a school session.
- `POST /api/v2/auth/refresh` and `POST /api/v2/auth/logout` — rotate/revoke refreshable sessions.
- `GET /api/v2/auth/me` and `GET /api/v2/auth/permissions` — current account and effective position permissions.
- `GET /api/v2/public/config` — non-secret OIDC/Firebase client configuration for the Android app.
- `POST /api/v2/admin/users` and `POST /api/v2/management/users` — create local accounts, subject to permissions.
- `GET /api/v2/admin/users`, `PATCH /api/v2/admin/users/{id}` — list/update accounts and deactivate/reactivate users.
- `PUT /api/v2/admin/staff-positions` — assign a position (director, deputy, homeroom teacher, DOP coordinator, mentor coordinator, teacher, mentor, librarian); only an existing admin can assign director/deputy.
- `POST /api/v2/admin/student-links` and `POST/DELETE /api/v2/admin/assignments` — explicitly associate students with mentors and teachers by subject.
- `GET /api/v2/management/dashboard`, `GET /api/v2/management/students`, `GET /api/v2/management/staff` — role-scoped management overview and rosters.
- `GET /api/v2/teachers/me/subjects` — list students explicitly assigned to the signed-in teacher by subject.
- `GET /api/v2/students` and `GET /api/v2/students/{id}` — role-scoped student list/details.
- `POST /api/v2/management/students/{id}/supplements`, `PATCH/DELETE /api/v2/management/supplements/{id}` — create/update/delete DOP records with permissions.
- `POST /api/v2/management/sync/supplements` and `GET /api/v2/management/sync/status` — import student-linked DOP rows from the selected workbook/JSON/HTTPS adapter.
- `POST /api/v2/devices/register`, `DELETE /api/v2/devices/me` — register and revoke FCM device tokens.
- `GET /api/v2/notifications`, `POST /api/v2/admin/notifications` — list visible notifications and create global, class, group, personal, emergency, or scheduled messages.
- `GET/PUT /api/v2/notifications/preferences` — opt in/out of server-generated DOP reminders.
- `GET /api/v2/announcements` — list announcements visible to the current user.
- `POST /api/v2/admin/announcements` — publish info, warning, or emergency notice.
- `GET /api/v2/admin/audit` and `GET /api/v2/management/audit` — inspect recent audit events with appropriate permissions.

Use the header `Authorization: Bearer <access_token>` on authenticated requests.
Example login body: `{"username":"admin","password":"<secret>"}`.
Example emergency notice body:
`{"title":"Учебная тревога","body":"Следуйте указаниям сотрудников школы.","severity":"emergency","audience":"all"}`.

## Emergency-notification limitations

The API sends a Firebase Cloud Messaging notification when Firebase is configured and
valid device tokens exist. The notification worker handles queued/scheduled messages and
creates idempotent 15-minute DOP reminders for students who enabled that preference. It
polls SQLite in the API container; keep the deployment to one worker process per database
unless a shared transactional database and worker coordination are configured. Device tokens are sent in batches of up to 500, matching FCM's
multicast limit; the API records a partial result when some deliveries succeed and others fail. It does not trigger or replace the school's PA/loudspeaker
system, fire-alarm hardware, 112, or any official emergency process. Push delivery is
best-effort; mobile OS settings, network coverage, battery restrictions, and provider
latency can delay or suppress it. Never rely on the app as the only alarm channel.
Use short, pre-approved templates and let school leadership authorize emergency
broadcasts. Do not include sensitive student information in global messages.

## Production hardening required before real student data

The app now has a school SSO sign-in entry and a role-aware portal for staff, student rosters,
DOP management, assignments, account lifecycle, notifications and sync status. The Flutter
schedule can refresh from `BaseSchedule` when the configured source has compatible columns;
the bundled schedule remains the offline fallback. Student-linked DOP rows are imported
through the portal's explicit sync action and unmatched rows are skipped rather than assigned
to the wrong student.

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
учётную запись «Поколение» один раз using `POST /api/v2/admin/sso-identities` with
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
