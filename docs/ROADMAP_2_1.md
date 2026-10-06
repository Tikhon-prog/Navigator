# Navigator 2.1 roadmap

## Completed in this package
- class-aware schedule storage
- current weekday default
- local next-lesson reminder scheduling
- extended supplements model/UI
- administrator login and roles
- SHA-256 password storage
- online API client
- Yandex Wiki grid backend skeleton
- cloud data workbook
- FCM integration skeleton
- source map/PDF bundle

## Next hardening pass
1. Replace approximate route graph edges with a digitized walkable corridor graph for all three floors.
2. Add explicit door/portal coordinates for each room instead of routing from room centers.
3. Add class-specific remote schedule versioning and conflict resolution.
4. Add authenticated admin sessions/JWT on the backend.
5. Add server-side password hashing with a salted slow hash (SHA-256 is kept only because it was explicitly requested for this prototype).
6. Add audit records for every admin mutation.
7. Register FCM tokens per class and send targeted schedule changes/announcements.
8. Add full admin CRUD for Classes, BaseSchedule, Supplements, Places, Announcements and Devices.
9. Add notification preferences and quiet hours.
