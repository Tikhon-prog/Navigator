# Navigator 2.1 — school navigator

Navigator 2.1 expands the previous offline map prototype into a functional school app architecture:

- three school floor maps;
- corridor route engine and thinner route overlay;
- search and arbitrary route start selection;
- class-based base schedules stored separately per class;
- current weekday selected by default;
- local Android lesson reminders;
- optional remote push architecture via Firebase Cloud Messaging;
- extended Supplements module with day/time/teacher/room/place/group/description and route to a room;
- administrator login with SHA-256 password hashes;
- superadmin/admin roles and local admin management;
- online API client;
- Yandex Wiki dynamic-table backend template;
- XLSX schema for the online data model;
- no informational "works offline" banner on the home screen;
- original school PDF and high-resolution source floor images included for future route-map refinement.

## Data model

`backend/Navigator_Master.xlsx` contains the first schema. The runtime model uses these logical tables:

Admins, Classes, BaseSchedule, Supplements, Rooms, Places, Announcements, Devices, AuditLog, Settings.

The important schedule rule is **class base schedule first**. A missing internet connection must not make a student use an old "last sync" snapshot as if it were today's source. The app keeps the class profile and its local base schedule, while online synchronization can publish a newer base dataset.

## Online backend

The Flutter app never receives a Yandex OAuth token. It talks to a HTTPS backend. The backend can use Yandex Wiki dynamic tables and a Yandex Cloud Function. See `backend/yandex_cloud_function/README.md`.

Yandex's official Wiki API supports creating dynamic tables and editing columns, rows and cells. The included `create_tables.py` creates the logical table set after you provide your own OAuth token and organization ID.

## Push notifications

Local reminders work through `flutter_local_notifications`. Remote push support is prepared with Firebase Cloud Messaging. Before remote push can actually deliver notifications, the Android Firebase project configuration (`google-services.json`) must be supplied for the target application. The app catches missing Firebase configuration instead of crashing.

## Initial admin

The prototype bootstrap account is:

- login: `admin`
- password: `admin`

Only the SHA-256 digest is stored in the client prototype. For a real deployment, the server must own authentication, rate limits, sessions/JWT and the audit log; the bootstrap account must be replaced before public use.
