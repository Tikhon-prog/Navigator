# Navigator — security model

## Current protections
- The Flutter app has no built-in default administrator credentials. First-run setup creates the first local administrator only when the local account store is empty.
- Local admin passwords are stored as salted, repeated SHA-256 hashes and compared in constant time. This is a prototype measure, not a substitute for a server-side Argon2id, scrypt, or bcrypt password KDF.
- Local login attempts are temporarily locked after repeated failures. The lockout and audit log live on the same device and can be altered by someone who controls that device.
- The optional online API accepts HTTPS for remote hosts. Plain HTTP is allowed only for loopback development addresses. Requests have a 10-second timeout.
- The FastAPI read API exposes only the intended school-data sheets. Generic sheet and schema routes reject Admins, AuditLog, Devices, and Settings; the Settings and Devices endpoints are disabled.
- The Yandex Cloud Function admin-login route returns HTTP 503 until real server-side authentication, rate limiting, session issuance, and authorization checks exist. Do not treat its current login route as production authentication.
- Backend errors returned to clients do not include raw provider exceptions.

## Important limitations
- Local admin accounts and permissions are stored in SharedPreferences. A person who can modify the app or its local data can bypass local-only checks. These checks are for accidental access control, not a security boundary against a device owner or a reverse engineer.
- `X-Navigator-Key` is a client-side identifier and must not be treated as a secret. Never put OAuth tokens, private API keys, or server credentials in Dart code, Flutter assets, or the APK.
- Public read endpoints are intentionally unauthenticated; only publish data that is appropriate for anyone with the endpoint URL to read.
- Production administrator features require server-side password hashing (Argon2id/scrypt/bcrypt), rate limiting, short-lived revocable sessions, authorization checks on every protected operation, audit logging, and HTTPS.

## Secrets handling
- Store real deployment credentials in the hosting provider's secret/environment settings. For local development, copy `backend/.env.example` to `backend/.env`; never commit the real `.env`.
- A Yandex OAuth token was found in a previously committed `backend/.env` and the file has been removed from the current branch. **That token must be revoked and replaced immediately.** Removing the file does not erase it from earlier Git commits; after revocation, purge the secret from repository history if the old history must no longer contain it.
- Never commit signing keys, `key.properties`, passwords, or generated Python bytecode.
