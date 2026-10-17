import os
import tempfile
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo
import unittest
from pathlib import Path
from unittest.mock import patch

from fastapi import HTTPException

from backend import school_api as core
from backend import notification_api as notifications


class NotificationScopeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.db_patch = patch.object(core, "DB_PATH", Path(self.tmp.name) / "notifications.sqlite3")
        self.db_patch.start()
        self.secret_patch = patch.object(core, "TOKEN_SECRET", "test-secret-that-is-long-enough-for-hmac-signing")
        self.secret_patch.start()
        self.env_patch = patch.dict(os.environ, {"NAVIGATOR_TOKEN_SECRET": "test-secret-that-is-long-enough-for-hmac-signing"})
        self.env_patch.start()
        core.init_db()
        notifications._init()
        with core._db() as db:
            for user_id, username, role, class_id in [
                ("admin1", "admin", "admin", None),
                ("teacher1", "teacher", "teacher", "8A"),
                ("student1", "student1", "student", "8A"),
                ("student2", "student2", "student", "8B"),
            ]:
                db.execute(
                    "INSERT INTO users(id,username,password_hash,role,display_name,class_id,created_at) VALUES(?,?,?,?,?,?,?)",
                    (user_id, username, core._hash_password("a sufficiently long test password"), role, username, class_id, core._utc_now()),
                )
            db.execute(
                "INSERT INTO teacher_subject_assignments(student_id,staff_id,subject,created_at) VALUES(?,?,?,?)",
                ("student1", "teacher1", "Mathematics", core._utc_now()),
            )

    def tearDown(self):
        self.env_patch.stop()
        self.secret_patch.stop()
        self.db_patch.stop()
        self.tmp.cleanup()

    def test_personal_notification_is_visible_only_to_recipient(self):
        body = notifications.NotificationBody(
            title="DOP reminder", body="Robotics starts at 15:00",
            kind="dop_reminder", target_type="user", target_id="student1",
        )
        created = notifications.create_notification(body, {"id": "admin1", "role": "admin"})
        self.assertEqual(created["kind"], "dop_reminder")
        self.assertEqual(len(notifications.list_notifications({"id": "student1", "role": "student", "class_id": "8A"})["data"]), 1)
        self.assertEqual(len(notifications.list_notifications({"id": "student2", "role": "student", "class_id": "8B"})["data"]), 0)

    def test_teacher_cannot_notify_unassigned_student(self):
        body = notifications.NotificationBody(
            title="Homework", body="Please check the task",
            kind="personal", target_type="user", target_id="student2",
        )
        with self.assertRaises(HTTPException) as raised:
            notifications.create_notification(body, {"id": "teacher1", "role": "teacher"})
        self.assertEqual(raised.exception.status_code, 403)

    def test_student_can_opt_in_to_server_dop_reminders(self):
        actor = {"id": "student1", "role": "student", "class_id": "8A"}
        saved = notifications.set_notification_preferences(
            notifications.NotificationPreferencesBody(dop_reminders_enabled=True), actor
        )
        self.assertTrue(saved["dop_reminders_enabled"])
        self.assertTrue(notifications.get_notification_preferences(actor)["dop_reminders_enabled"])

    def test_opted_in_student_gets_idempotent_future_dop_reminder(self):
        actor = {"id": "student1", "role": "student", "class_id": "8A"}
        notifications.set_notification_preferences(
            notifications.NotificationPreferencesBody(dop_reminders_enabled=True), actor
        )
        tomorrow = datetime.now(ZoneInfo("Europe/Moscow")).date() + timedelta(days=1)
        # A fixed late time tomorrow keeps the test independent of the runner's clock.
        start_time = "23:55"
        with core._db() as db:
            db.execute(
                "INSERT INTO student_supplements(id,student_id,title,weekday,time,teacher,room,status,updated_at) VALUES(?,?,?,?,?,?,?,?,?)",
                ("dop-reminder-1", "student1", "Робототехника", tomorrow.isoweekday(), start_time, "Учитель", "317", "active", core._utc_now()),
            )
        self.assertGreaterEqual(notifications._enqueue_dop_reminders(), 1)
        with core._db() as db:
            first = db.execute("SELECT COUNT(*) AS n FROM dop_reminder_occurrences WHERE supplement_id='dop-reminder-1'").fetchone()["n"]
        notifications._enqueue_dop_reminders()
        with core._db() as db:
            second = db.execute("SELECT COUNT(*) AS n FROM dop_reminder_occurrences WHERE supplement_id='dop-reminder-1'").fetchone()["n"]
        self.assertEqual(first, 1)
        self.assertEqual(second, 1)

    def test_teacher_cannot_broadcast_to_everyone(self):
        body = notifications.NotificationBody(title="Message", body="Test")
        with self.assertRaises(HTTPException) as raised:
            notifications.create_notification(body, {"id": "teacher1", "role": "teacher"})
        self.assertEqual(raised.exception.status_code, 403)


if __name__ == "__main__":
    unittest.main()
