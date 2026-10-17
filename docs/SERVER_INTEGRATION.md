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
- `teacher`: can inspect students in the teacher's own `class_id` and students
  explicitly linked to them.
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
- `POST /api/v2/admin/student-links` — explicitly associate a student with a mentor/teacher.
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
throttle is process-local and is not a substitute for edge rate limiting.
