import os
import tempfile
import unittest
from unittest.mock import patch

from fastapi import HTTPException

from backend import school_api as api
from backend import rbac_api


class SchoolApiTests(unittest.TestCase):
    def setUp(self):
        api.login._attempts = {}
        self.tmp = tempfile.TemporaryDirectory()
        self.env = patch.dict(os.environ, {"NAVIGATOR_TOKEN_SECRET": "test-secret-that-is-long-enough-for-hmac-signing"})
        self.env.start()
        self.path = patch.object(api, "DB_PATH", __import__("pathlib").Path(self.tmp.name) / "test.sqlite3")
        self.path.start()
        self.secret = patch.object(api, "TOKEN_SECRET", "test-secret-that-is-long-enough-for-hmac-signing")
        self.secret.start()
        api.init_db()
        with api._db() as db:
            db.execute("INSERT INTO users(id,username,password_hash,role,display_name,class_id,created_at) VALUES(?,?,?,?,?,?,?)",
                       ("admin1", "admin", api._hash_password("correct horse battery"), "admin", "Admin", None, api._utc_now()))
            db.execute("INSERT INTO users(id,username,password_hash,role,display_name,class_id,created_at) VALUES(?,?,?,?,?,?,?)",
                       ("mentor1", "mentor", api._hash_password("correct horse battery"), "mentor", "Mentor", None, api._utc_now()))
            db.execute("INSERT INTO users(id,username,password_hash,role,display_name,class_id,created_at) VALUES(?,?,?,?,?,?,?)",
                       ("teacher1", "teacher", api._hash_password("correct horse battery"), "teacher", "Teacher", "8A", api._utc_now()))
            db.execute("INSERT INTO users(id,username,password_hash,role,display_name,class_id,created_at) VALUES(?,?,?,?,?,?,?)",
                       ("student1", "student", api._hash_password("correct horse battery"), "student", "Student", "8A", api._utc_now()))
            db.execute("INSERT INTO users(id,username,password_hash,role,display_name,class_id,created_at) VALUES(?,?,?,?,?,?,?)",
                       ("student2", "otherstudent", api._hash_password("correct horse battery"), "student", "Other Student", "8B", api._utc_now()))
            db.execute("INSERT INTO student_links(student_id,staff_id,link_type,subject,created_at) VALUES(?,?,?,?,?)",
                       ("student1", "mentor1", "mentor", "", api._utc_now()))
            db.execute("INSERT INTO teacher_subject_assignments(student_id,staff_id,subject,created_at) VALUES(?,?,?,?)",
                       ("student1", "teacher1", "Mathematics", api._utc_now()))
            db.execute("INSERT INTO student_supplements(id,student_id,title,weekday,time,teacher,room,status,updated_at) VALUES(?,?,?,?,?,?,?,?,?)",
                       ("dop1", "student1", "Robotics", 3, "15:00", "Mentor", "317", "active", api._utc_now()))

    def tearDown(self):
        self.path.stop()
        self.secret.stop()
        self.env.stop()
        self.tmp.cleanup()

    def test_password_hash_is_salted_and_verifies(self):
        first = api._hash_password("password")
        second = api._hash_password("password")
        self.assertNotEqual(first, second)
        self.assertTrue(api._verify_password("password", first))
        self.assertFalse(api._verify_password("wrong", first))

    def test_token_signature_and_expiry(self):
        with api._db() as db:
            user = db.execute("SELECT * FROM users WHERE id='student1'").fetchone()
        token = api._make_token(user)
        self.assertEqual(api._decode_token(token)["sub"], "student1")
        with self.assertRaises(HTTPException):
            api._decode_token(token + "tampered")

    def test_non_admin_password_login_is_disabled_by_default(self):
        from starlette.requests import Request
        request = Request({
            "type": "http", "method": "POST", "path": "/api/v2/auth/login",
            "scheme": "http", "server": ("testserver", 80),
            "client": ("127.0.0.1", 12345), "query_string": b"", "headers": [],
        })
        with patch.dict(os.environ, {"NAVIGATOR_ALLOW_NON_SSO_PASSWORD_LOGIN": "false"}):
            with self.assertRaises(HTTPException) as raised:
                api.login(api.LoginBody(username="student1", password="correct horse battery"), request)
        self.assertEqual(raised.exception.status_code, 403)

    def test_admin_password_login_remains_available_for_technical_recovery(self):
        from starlette.requests import Request
        request = Request({
            "type": "http", "method": "POST", "path": "/api/v2/auth/login",
            "scheme": "http", "server": ("testserver", 80),
            "client": ("127.0.0.1", 12346), "query_string": b"", "headers": [],
        })
        result = api.login(api.LoginBody(username="admin", password="correct horse battery"), request)
        self.assertEqual(result["user"]["role"], "admin")
        self.assertEqual(api._decode_token(result["access_token"])["auth_method"], "password")

    def test_password_session_for_student_is_revoked_when_local_login_is_disabled(self):
        with api._db() as db:
            user = db.execute("SELECT * FROM users WHERE id='student1'").fetchone()
        session = api._issue_session(user, auth_method="password")
        with patch.dict(os.environ, {"NAVIGATOR_ALLOW_NON_SSO_PASSWORD_LOGIN": "false"}):
            with self.assertRaises(HTTPException) as raised:
                api.refresh_session(api.RefreshBody(refresh_token=session["refresh_token"]))
        self.assertEqual(raised.exception.status_code, 403)
        with api._db() as db:
            row = db.execute("SELECT revoked_at FROM refresh_tokens WHERE token_hash=?",
                             (__import__("hashlib").sha256(session["refresh_token"].encode()).hexdigest(),)).fetchone()
        self.assertIsNotNone(row["revoked_at"])

    def test_refresh_token_rotates_and_cannot_be_reused(self):
        with api._db() as db:
            user = db.execute("SELECT * FROM users WHERE id='student1'").fetchone()
        session = api._issue_session(user, auth_method="sso")
        rotated = api.refresh_session(api.RefreshBody(refresh_token=session["refresh_token"]))
        self.assertNotEqual(session["refresh_token"], rotated["refresh_token"])
        self.assertNotEqual(session["access_token"], rotated["access_token"])
        with self.assertRaises(HTTPException) as raised:
            api.refresh_session(api.RefreshBody(refresh_token=session["refresh_token"]))
        self.assertEqual(raised.exception.status_code, 401)

    def test_logout_revokes_refresh_token(self):
        with api._db() as db:
            user = db.execute("SELECT * FROM users WHERE id='student1'").fetchone()
        session = api._issue_session(user, auth_method="sso")
        self.assertEqual(api.logout_session(api.RefreshBody(refresh_token=session["refresh_token"]))["status"], "logged_out")
        with self.assertRaises(HTTPException):
            api.refresh_session(api.RefreshBody(refresh_token=session["refresh_token"]))

    def test_logout_revokes_access_and_refresh_tokens(self):
        with api._db() as db:
            user = db.execute("SELECT * FROM users WHERE id='student1'").fetchone()
        session = api._issue_session(user, auth_method="sso")
        api.logout_session(
            api.RefreshBody(refresh_token=session["refresh_token"]),
            authorization="Bearer " + session["access_token"],
        )
        with self.assertRaises(HTTPException) as raised:
            api.current_user("Bearer " + session["access_token"])
        self.assertEqual(raised.exception.status_code, 401)
        with self.assertRaises(HTTPException):
            api.refresh_session(api.RefreshBody(refresh_token=session["refresh_token"]))

    def test_logout_can_revoke_current_device_when_access_token_is_expired(self):
        with api._db() as db:
            user = db.execute("SELECT * FROM users WHERE id='student1'").fetchone()
        with patch.object(api, "TOKEN_TTL_SECONDS", -1):
            session = api._issue_session(user, auth_method="sso")
        device_token = "fcm-test-token-that-is-long-enough-for-device-revocation"
        with api._db() as db:
            db.execute(
                "INSERT INTO devices(id,user_id,fcm_token,platform,active,updated_at) VALUES(?,?,?,?,1,?)",
                ("device1", "student1", device_token, "android", api._utc_now()),
            )
        result = api.logout_session(
            api.RefreshBody(refresh_token=session["refresh_token"], device_token=device_token),
            authorization="Bearer " + session["access_token"],
        )
        self.assertEqual(result["status"], "logged_out")
        with api._db() as db:
            device = db.execute("SELECT active FROM devices WHERE id='device1'").fetchone()
        self.assertEqual(device["active"], 0)

    def test_old_access_token_stays_invalid_after_account_reactivation(self):
        with api._db() as db:
            user = db.execute("SELECT * FROM users WHERE id='student1'").fetchone()
        session = api._issue_session(user, auth_method="sso")
        with api._db() as db:
            db.execute("UPDATE users SET active=0,token_version=token_version+1 WHERE id='student1'")
            db.execute("UPDATE users SET active=1 WHERE id='student1'")
        with self.assertRaises(HTTPException) as raised:
            api.current_user("Bearer " + session["access_token"])
        self.assertEqual(raised.exception.status_code, 401)

    def test_mentor_only_sees_linked_students(self):
        actor = {"id": "mentor1", "role": "mentor", "class_id": None}
        result = api.list_students(actor)
        self.assertEqual([x["id"] for x in result["data"]], ["student1"])

    def test_teacher_sees_only_explicit_subject_assignments(self):
        actor = {"id": "teacher1", "role": "teacher", "class_id": "8A"}
        result = api.list_students(actor)
        self.assertEqual([x["id"] for x in result["data"]], ["student1"])

    def test_student_cannot_read_unlinked_other_student(self):
        actor = {"id": "student2", "role": "student", "class_id": "8B"}
        with self.assertRaises(HTTPException) as raised:
            api.get_student("student1", actor)
        self.assertEqual(raised.exception.status_code, 404)

    def test_mentor_can_view_linked_student_supplements(self):
        actor = {"id": "mentor1", "role": "mentor", "class_id": None}
        result = api.get_student("student1", actor)
        self.assertEqual(result["supplements"][0]["title"], "Robotics")
        with self.assertRaises(HTTPException):
            api.get_student("student2", actor)

    def test_teacher_details_hide_private_supplements(self):
        actor = {"id": "teacher1", "role": "teacher", "class_id": "8A"}
        result = api.get_student("student1", actor)
        self.assertEqual(result["supplements"], [])
        self.assertEqual(result["staff"][0]["subject"], "Mathematics")

    def test_students_audience_is_visible_to_student_accounts(self):
        with api._db() as db:
            db.execute("INSERT INTO announcements(id,title,body,severity,audience,created_by,created_at) VALUES(?,?,?,?,?,?,?)",
                       ("notice1", "Notice", "Body", "info", "students", "admin1", api._utc_now()))
        result = api.list_announcements({"id": "student1", "role": "student", "class_id": "8A"})
        self.assertEqual([item["id"] for item in result["data"]], ["notice1"])

    def test_announcement_push_fails_safely_without_firebase(self):
        with patch.object(api, "_send_push", return_value=("firebase_not_configured", 0)):
            with api._db() as db:
                admin = db.execute("SELECT * FROM users WHERE id='admin1'").fetchone()
            actor = api._public_user(admin)
            result = api.create_announcement(api.AnnouncementBody(title="Fire alarm", body="Leave by the nearest safe exit", severity="emergency"), actor)
        self.assertEqual(result["push_status"], "firebase_not_configured")
        self.assertEqual(result["severity"], "emergency")

    def test_homeroom_teacher_can_publish_only_to_assigned_class(self):
        actor = {"id": "teacher1", "role": "teacher", "class_id": None}
        with patch.object(rbac_api, "_position", return_value=("homeroom_teacher", "8A")), \
             patch.object(api, "_send_push", return_value=("no_registered_devices", 0)):
            result = api.create_announcement(
                api.AnnouncementBody(title="8A notice", body="Bring workbook", audience="class", class_id="8A"),
                actor,
            )
            self.assertEqual(result["class_id"], "8A")
            with self.assertRaises(HTTPException) as raised:
                api.create_announcement(
                    api.AnnouncementBody(title="8B notice", body="Wrong class", audience="class", class_id="8B"),
                    actor,
                )
            self.assertEqual(raised.exception.status_code, 403)
            with self.assertRaises(HTTPException) as raised:
                api.create_announcement(
                    api.AnnouncementBody(title="Global notice", body="Not allowed", audience="all"),
                    actor,
                )
            self.assertEqual(raised.exception.status_code, 403)

    def test_teacher_can_have_multiple_subjects_for_same_student(self):
        actor = {"id": "admin1", "role": "admin"}
        first = api.create_student_link(
            api.LinkBody(student_id="student1", staff_id="teacher1", link_type="teacher", subject="Physics"),
            actor,
        )
        second = api.create_student_link(
            api.LinkBody(student_id="student1", staff_id="teacher1", link_type="teacher", subject="Chemistry"),
            actor,
        )
        self.assertEqual(first["subject"], "Physics")
        self.assertEqual(second["subject"], "Chemistry")
        roster = api.teacher_subject_roster({"id": "teacher1", "role": "teacher"})
        self.assertEqual({row["subject"] for row in roster["data"]}, {"Chemistry", "Mathematics", "Physics"})


if __name__ == "__main__":
    unittest.main()
