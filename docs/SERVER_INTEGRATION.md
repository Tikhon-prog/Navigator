# Серверная интеграция школы «Поколение»

This branch adds a first usable, separately versioned service API at `/api/v2`.
The existing workbook-backed `/api/*` endpoints remain read-only for public reference data
(classes, base timetable, rooms, places, and school-wide/class-targeted announcements).
The `Supplements` workbook sheet is now internal-only: generic `/api/data/Supplements`,
`/api/schema/Supplements`, and the legacy `/api/supplements` endpoint do not expose the
whole student DOP roster. An authorized staff member imports it through the authenticated
sync route. The new service stores identities, explicit mentor/teacher relationships,
student-specific supplements, registered devices, announcements, and audit events in SQLite.

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

## First-run mobile server URL

The server `.env` configures the server, but cannot be read directly by an already-built APK. For a preconfigured Android install, set the non-secret GitHub repository variable `POKOLENIE_API_BASE_URL` to the public HTTPS API origin, for example `https://api.school.example`. The current Flutter CI embeds it as a default in the release APK; new installs then enable online mode automatically. No iOS build workflow is currently configured. Existing device settings are respected, and the value can still be changed in the app's server settings. Do not put access tokens, OAuth secrets or Firebase service-account credentials in this variable.

## Environment

Required for authenticated endpoints:
- `NAVIGATOR_TOKEN_SECRET`: random secret, at least 32 characters; keep it outside Git. The example uses `CHANGE_ME` deliberately; authentication will remain unavailable until you replace it with a real random value.
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
- `NAVIGATOR_OIDC_ISSUER`, optional `NAVIGATOR_OIDC_JWKS_URL` and `NAVIGATOR_OIDC_USERINFO_URL`, plus `NAVIGATOR_OIDC_CLIENT_ID` and `NAVIGATOR_OIDC_REDIRECT_URI`: values registered by school IT. UserInfo/JWKS endpoints are discovered automatically when omitted. The backend verifies the ID-token signature/audience via the IdP JWKS (or OIDC discovery) and compares its subject to UserInfo. The redirect URI must match the Android intent filter and identity-provider registration.
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

- `POST /api/v2/auth/login` — local username/password session, intended for technical admins by default; non-admin local password login is disabled unless `NAVIGATOR_ALLOW_NON_SSO_PASSWORD_LOGIN=true` is explicitly approved.
- `POST /api/v2/auth/sso` — verify the OIDC ID token and UserInfo subject, then issue a school session.
- `POST /api/v2/auth/refresh` and `POST /api/v2/auth/logout` — rotate/revoke refreshable sessions.
- `GET /api/v2/auth/me` and `GET /api/v2/auth/permissions` — current account and effective position permissions.
- `GET /api/v2/public/config` — non-secret OIDC/Firebase client configuration for the Android app.
- `GET /api/v2/health/ready` — checks that the token secret is not a placeholder and that Classes/BaseSchedule source data are available; reports readiness flags for OIDC and FCM without revealing credentials.
- Legacy `GET /api/supplements` returns HTTP 403. Use `POST /api/v2/management/sync/supplements` followed by authenticated student/staff endpoints instead.
- `POST /api/v2/admin/users` and `POST /api/v2/management/users` — create local accounts, subject to permissions.
- `GET /api/v2/admin/users`, `PATCH /api/v2/admin/users/{id}` — list/update accounts and deactivate/reactivate users.
- `PUT /api/v2/admin/staff-positions` — assign a position (director, deputy, homeroom teacher, DOP coordinator, mentor coordinator, teacher, mentor, librarian); only an existing admin can assign director/deputy.
- `POST /api/v2/admin/student-links` and `POST/DELETE /api/v2/admin/assignments` — explicitly associate students with mentors and teachers by subject.
- `GET /api/v2/management/dashboard`, `GET /api/v2/management/students`, `GET /api/v2/management/staff` — role-scoped management overview and rosters.
- `GET /api/v2/teachers/me/subjects` — list students explicitly assigned to the signed-in teacher by subject.
- `GET /api/v2/students` and `GET /api/v2/students/{id}` — role-scoped student list/details.
- `POST /api/v2/management/students/{id}/supplements`, `PATCH/DELETE /api/v2/management/supplements/{id}` — create/update/delete DOP records with permissions.
- `POST /api/v2/management/sync/supplements` and `GET /api/v2/management/sync/status` — import student-linked DOP rows from the selected workbook/JSON/HTTPS adapter. Unmatched rows are skipped; matching by display name is allowed only when unambiguous.
- `POST /api/v2/management/sync/teacher-assignments` — rebuild subject links from the base timetable. If the source is incompletely mapped, previous schedule-derived assignments are preserved. Subjects explicitly split across groups with different teachers are not assigned class-wide; configure those student-level relationships manually in the portal.
- `POST /api/v2/management/sync/teacher-assignments` and `PUT /api/v2/admin/schedule-teacher-aliases` — derive teacher/student/subject access from the authoritative timetable, with explicit aliases when timetable teacher names differ from account names.
- `GET /api/v2/announcements/workbook` — class-scoped workbook announcements; public announcement routes intentionally return school-wide notices only.
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


## School SSO setup

The Android app uses OpenID Connect Authorization Code + PKCE through the school's identity
provider. It sends both the returned ID token and access token to `POST /api/v2/auth/sso`.
The server verifies the ID-token signature using the provider's JWKS, checks issuer,
audience and expiration, calls the configured/discovered HTTPS UserInfo endpoint, and
requires the ID-token subject and UserInfo subject to match. Use the exact issuer and
client registration values from school IT; do not guess an issuer or reuse another app's
client ID.

An existing local account must normally be linked by an administrator using
`POST /api/v2/admin/sso-identities` with the stable provider subject (not an email
address guessed from the username). Trusted-claim auto-linking/provisioning is optional
and disabled by default. Enable it only after school IT confirms that the configured
username, role and class claims are controlled by the IdP and cannot be user-edited.
Administrative-account provisioning remains separately disabled unless explicitly
approved. The app's redirect URI must match the URI registered for the Android client. Access and refresh tokens are stored using platform secure storage (Android Keystore-backed encrypted storage / Apple Keychain), with a one-time migration from the older preferences-based token keys. Password login is restricted to technical administrators by default; do not enable non-SSO password login without a school-approved fallback policy.

## Notifications and delivery

- `POST /api/v2/admin/notifications` creates global, class, group, personal, emergency,
  or scheduled messages, subject to role/position and recipient-scope checks.
- `GET /api/v2/notifications` returns only records visible to the current account.
- `GET/PUT /api/v2/notifications/preferences` stores each student's opt-in choice for
  server-generated DOP reminders. The worker generates deduplicated reminders 15 minutes
  before active, timed supplements and records delivery status.
- Notification groups support `GET/POST /api/v2/admin/notification-groups`,
  `GET /api/v2/admin/notification-groups/{id}/members`,
  `POST /api/v2/admin/notification-groups/{id}/members`,
  `DELETE /api/v2/admin/notification-groups/{id}/members/{user_id}`, and
  `DELETE /api/v2/admin/notification-groups/{id}`. Group administration is available
  only to technical admins and staff with assignment-management permission.
- The delivery worker retries only transient provider-level failures with bounded
  exponential backoff. Missing Firebase credentials/packages, no registered recipients,
  and partial deliveries are surfaced rather than endlessly retried. A partial send is
  not automatically resent because that could duplicate a message for people who received it.
- `push_status` and `delivery_status` are operational signals, not proof that a person
  opened or read a notification. FCM and mobile OS settings are best-effort and can delay
  or suppress delivery.

Never use the app as the only channel for emergencies. It does not replace the school's
official alarm/PA process or emergency services. Global and emergency templates should
be approved by school leadership and must not contain sensitive student data.

## Multiple school-data sources

Set `NAVIGATOR_DATA_SOURCE` to one of:

- `yandex` (default): existing workbook and `YANDEX_OAUTH_TOKEN` flow.
- `json`: read allowlisted sheet names from `NAVIGATOR_DATA_JSON_PATH`, a local UTF-8
  JSON object whose values are arrays of row objects.
- `http`: request `{NAVIGATOR_DATA_API_URL}/{SheetName}`; the endpoint may return a JSON
  array or an object with a `data` array. Optional bearer token:
  `NAVIGATOR_DATA_API_TOKEN`.

Public workbook reads remain allowlisted/read-only. The authenticated account, assignments,
private notifications and device registrations stay in the service database. The current
DOP and teacher-assignment sync adapters map compatible source rows, skip unmatched
records, and log each run. They do not automatically know which columns the actual school
system uses; confirm and map the school's real schema before enabling automatic sync on
live data.

## Deployment and production review

For a first test deployment, copy `.env.example` to `.env`, fill the values supplied by
school IT, then run `docker compose up --build -d`. SQLite persists in the
`navigator_data` volume. The container binds to `127.0.0.1:8000`; expose it only behind
the school's HTTPS reverse proxy. Set the GitHub repository variable
`POKOLENIE_API_BASE_URL` to the public HTTPS API origin before creating a preconfigured
APK. It is a public URL, not a secret. Server secrets and the Firebase service-account
credentials must remain server-side.

Before storing real student data, school leadership/IT must approve privacy/legal
requirements, SSO claims, role mapping, retention and backups. Test backup restoration,
database migration, account deactivation, device revocation and emergency message policy.
Use centralized request-rate limiting and monitoring; the current login throttle is
process-local. Keep one API worker for the SQLite-backed notification worker, or move to
a shared transactional database and explicit multi-worker coordination before scaling
horizontally. This is a functional integration scaffold, not a school-approved production
deployment until these checks are complete.
