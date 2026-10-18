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
                ("student3", "student3", "student", "8А"),
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

    def test_director_can_publish_schoolwide_notification_visible_to_all_accounts(self):
        body = notifications.NotificationBody(
            title="Общешкольное объявление",
            body="Информация для всех учеников и сотрудников",
            kind="global", target_type="all",
        )
        with patch("backend.rbac_api._position", return_value=("director", None)):
            created = notifications.create_notification(body, {"id": "teacher1", "role": "teacher", "class_id": "8A"})
        self.assertEqual(created["kind"], "global")
        self.assertEqual(created["target_type"], "all")
        for actor in (
            {"id": "student1", "role": "student", "class_id": "8A"},
            {"id": "student2", "role": "student", "class_id": "8B"},
            {"id": "admin1", "role": "admin"},
        ):
            with self.subTest(role=actor["role"], user_id=actor["id"]):
                feed = notifications.list_notifications(actor)["data"]
                self.assertIn("Общешкольное объявление", [item["title"] for item in feed])

    def test_non_leadership_cannot_publish_schoolwide_notification(self):
        body = notifications.NotificationBody(
            title="Not allowed", body="Students cannot broadcast to the whole school",
            kind="global", target_type="all",
        )
        with self.assertRaises(HTTPException) as raised:
            notifications.create_notification(body, {"id": "student1", "role": "student", "class_id": "8A"})
        self.assertEqual(raised.exception.status_code, 403)

    def test_leadership_can_review_and_cancel_notifications(self):
        body = notifications.NotificationBody(
            title="Scheduled school alert", body="All school",
            kind="global", target_type="all",
        )
        created = notifications.create_notification(body, {"id": "admin1", "role": "admin"})
        history = notifications.list_admin_notifications(100, {"id": "admin1", "role": "admin"})["data"]
        self.assertIn(created["id"], [row["id"] for row in history])
        cancelled = notifications.cancel_notification(created["id"], {"id": "admin1", "role": "admin"})
        self.assertEqual(cancelled["status"], "cancelled")
        self.assertFalse(cancelled["push_already_sent"])
        self.assertEqual(notifications.list_notifications({"id": "student1", "role": "student", "class_id": "8A"})["data"], [])

    def test_teacher_without_leadership_position_cannot_view_or_cancel_schoolwide_history(self):
        with self.assertRaises(HTTPException) as raised:
            notifications.list_admin_notifications(100, {"id": "teacher1", "role": "teacher"})
        self.assertEqual(raised.exception.status_code, 403)
        with self.assertRaises(HTTPException) as raised:
            notifications.cancel_notification("missing-id", {"id": "teacher1", "role": "teacher"})
        self.assertEqual(raised.exception.status_code, 403)

    def test_personal_notification_is_visible_only_to_recipient(self):
        with core._db() as db:
            db.execute(
                "INSERT INTO student_supplements(id,student_id,title,weekday,time,teacher,room,status,updated_at) VALUES(?,?,?,?,?,?,?,?,?)",
                ("active-dop", "student1", "Robotics", 3, "15:00", "Teacher", "317", "active", core._utc_now()),
            )
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

    def test_student_cannot_create_server_dop_reminder_for_another_user(self):
        body = notifications.NotificationBody(
            title="DOP reminder", body="Not allowed",
            kind="dop_reminder", target_type="user", target_id="student2",
        )
        with self.assertRaises(HTTPException) as raised:
            notifications.create_notification(body, {"id": "student1", "role": "student", "class_id": "8A"})
        self.assertEqual(raised.exception.status_code, 403)

    def test_coordinator_cannot_send_personal_message_to_staff_account(self):
        with core._db() as db:
            db.execute(
                "INSERT INTO users(id,username,password_hash,role,display_name,class_id,created_at) VALUES(?,?,?,?,?,?,?)",
                ("teacher2", "teacher2", core._hash_password("a sufficiently long test password"),
                 "teacher", "Other teacher", None, core._utc_now()),
            )
        body = notifications.NotificationBody(
            title="Message", body="Only student recipients are allowed",
            kind="personal", target_type="user", target_id="teacher2",
        )
        with patch("backend.rbac_api._position", return_value=("dop_coordinator", None)):
            with self.assertRaises(HTTPException) as raised:
                notifications.create_notification(body, {"id": "teacher1", "role": "teacher", "class_id": "8A"})
        self.assertEqual(raised.exception.status_code, 403)

    def test_homeroom_teacher_receives_notifications_for_assigned_class(self):
        body = notifications.NotificationBody(
            title="Class notice", body="Visible to 8A",
            kind="targeted", target_type="class", target_id="8A",
        )
        with patch("backend.rbac_api._position", return_value=("director", None)):
            notifications.create_notification(body, {"id": "admin1", "role": "admin"})
        with patch("backend.rbac_api._position", return_value=("homeroom_teacher", "8A")):
            result = notifications.list_notifications({"id": "teacher1", "role": "teacher", "class_id": None})
        self.assertEqual([row["title"] for row in result["data"]], ["Class notice"])

    def test_group_manager_can_create_group_and_add_active_member(self):
        actor = {"id": "admin1", "role": "admin"}
        group = notifications.create_group(notifications.GroupBody(name="Math Olympiad"), actor)
        result = notifications.add_group_member(
            group["id"], notifications.GroupMemberBody(user_id="student1"), actor
        )
        self.assertEqual(result["status"], "added")
        members = notifications.list_group_members(group["id"], actor)
        self.assertEqual([item["id"] for item in members["data"]], ["student1"])

    def test_assignment_coordinator_can_manage_groups_but_teacher_cannot(self):
        manager = {"id": "teacher1", "role": "teacher", "class_id": "8A"}
        with patch("backend.rbac_api._position", return_value=("mentor_coordinator", None)):
            group = notifications.create_group(notifications.GroupBody(name="Mentor Cohort"), manager)
            self.assertEqual(group["name"], "Mentor Cohort")
        with patch("backend.rbac_api._position", return_value=(None, None)):
            with self.assertRaises(HTTPException) as raised:
                notifications.create_group(notifications.GroupBody(name="Unauthorized"), manager)
        self.assertEqual(raised.exception.status_code, 403)

    def test_group_notification_is_visible_only_to_members(self):
        admin = {"id": "admin1", "role": "admin"}
        group = notifications.create_group(notifications.GroupBody(name="Private group"), admin)
        notifications.add_group_member(group["id"], notifications.GroupMemberBody(user_id="student1"), admin)
        body = notifications.NotificationBody(
            title="Group notice", body="Only members see this",
            kind="targeted", target_type="group", target_id=group["id"],
        )
        notifications.create_notification(body, admin)
        self.assertEqual(
            [item["title"] for item in notifications.list_notifications({"id": "student1", "role": "student", "class_id": "8A"})],
            ["Group notice"],
        )
        self.assertEqual(
            notifications.list_notifications({"id": "student2", "role": "student", "class_id": "8B"})["data"],
            [],
        )

    def test_class_notification_is_visible_across_cyrillic_latin_class_labels(self):
        notice = notifications.NotificationBody(
            title="8A notice", body="For class 8A",
            kind="targeted", target_type="class", target_id="8A",
        )
        notifications.create_notification(notice, {"id": "admin1", "role": "admin"})
        result = notifications.list_notifications({"id": "student3", "role": "student", "class_id": "8А"})
        self.assertEqual([item["title"] for item in result["data"]], ["8A notice"])

    def test_class_push_recipients_normalize_cyrillic_latin_labels(self):
        with core._db() as db:
            db.executemany(
                "INSERT INTO devices(id,user_id,fcm_token,platform,active,updated_at) VALUES(?,?,?,?,1,?)",
                [
                    ("device1", "student1", "token-for-student-one-0000000001", "android", core._utc_now()),
                    ("device2", "student2", "token-for-student-two-0000000002", "android", core._utc_now()),
                    ("device3", "student3", "token-for-student-three-000003", "android", core._utc_now()),
                ],
            )
            tokens = notifications._recipient_tokens(db, {"target_type": "class", "target_id": "8A"})
        self.assertEqual(set(tokens), {"token-for-student-one-0000000001", "token-for-student-three-000003"})

    def test_transient_firebase_delivery_error_is_scheduled_for_retry(self):
        notification_id = "retry-notice-1"
        with core._db() as db:
            db.execute(
                "INSERT INTO notifications(id,title,body,kind,target_type,target_id,created_by,created_at,delivery_status) "
                "VALUES(?,?,?,?,?,?,?,?,?)",
                (notification_id, "Retry", "Temporary failure test", "personal", "user", "student1",
                 "admin1", notifications._now(), "queued"),
            )
        with patch.object(core, "_send_push", return_value=("provider_error", 0)):
            self.assertEqual(notifications._dispatch_due_notifications(), 1)
        with core._db() as db:
            row = db.execute(
                "SELECT delivery_status,delivery_attempts,next_attempt_at,push_status FROM notifications WHERE id=?",
                (notification_id,),
            ).fetchone()
        self.assertEqual(row["delivery_status"], "retry")
        self.assertEqual(row["delivery_attempts"], 1)
        self.assertIsNotNone(row["next_attempt_at"])
        self.assertEqual(row["push_status"], "provider_error")

    def test_mentor_coordinator_cannot_add_staff_to_delivery_group(self):
        with core._db() as db:
            db.execute(
                "INSERT INTO users(id,username,password_hash,role,display_name,created_at) VALUES(?,?,?,?,?,?)",
                ("teacher2", "teacher2", core._hash_password("a sufficiently long test password"),
                 "teacher", "Other Teacher", core._utc_now()),
            )
        actor = {"id": "teacher1", "role": "teacher"}
        with patch("backend.rbac_api._position", return_value=("mentor_coordinator", None)):
            group = notifications.create_group(notifications.GroupBody(name="Student Delivery Group"), actor)
            with self.assertRaises(HTTPException) as raised:
                notifications.add_group_member(
                    group["id"], notifications.GroupMemberBody(user_id="teacher2"), actor
                )
        self.assertEqual(raised.exception.status_code, 403)

    def test_mentor_coordinator_cannot_broadcast_to_mixed_staff_group(self):
        with core._db() as db:
            db.execute(
                "INSERT INTO users(id,username,password_hash,role,display_name,created_at) VALUES(?,?,?,?,?,?)",
                ("teacher2", "teacher2", core._hash_password("a sufficiently long test password"),
                 "teacher", "Other Teacher", core._utc_now()),
            )
        admin = {"id": "admin1", "role": "admin"}
        group = notifications.create_group(notifications.GroupBody(name="Mixed Group"), admin)
        notifications.add_group_member(group["id"], notifications.GroupMemberBody(user_id="teacher2"), admin)
        with patch("backend.rbac_api._position", return_value=("mentor_coordinator", None)):
            body = notifications.NotificationBody(
                title="Private", body="Should not reach staff", kind="targeted",
                target_type="group", target_id=group["id"],
            )
            with self.assertRaises(HTTPException) as raised:
                notifications.create_notification(body, {"id": "teacher1", "role": "teacher"})
        self.assertEqual(raised.exception.status_code, 403)

    def test_teacher_cannot_broadcast_to_everyone(self):
        body = notifications.NotificationBody(title="Message", body="Test")
        with self.assertRaises(HTTPException) as raised:
            notifications.create_notification(body, {"id": "teacher1", "role": "teacher"})
        self.assertEqual(raised.exception.status_code, 403)


if __name__ == "__main__":
    unittest.main()
