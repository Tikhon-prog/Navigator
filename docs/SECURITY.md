# Security notes

- The requested SHA-256 scheme is implemented for the prototype.
- Do not place Yandex OAuth tokens, Firebase server keys or other private credentials in Flutter assets or Dart source.
- The included `admin/admin` bootstrap is for development only.
- Production authentication should be performed by the server with salted password hashing, sessions/JWT, rate limiting and audit logs.
- The XLSX file is a schema/template. Do not use it as a public password database.
