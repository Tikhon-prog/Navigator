import os
import tempfile
import unittest
from unittest.mock import patch

from fastapi import HTTPException

from backend import school_api as api


class SchoolApiTests(unittest.TestCase):
    def setUp(self):
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
            db.execute("INSERT INTO student_links(student_id,staff_id,link_type,subject,created_at) VALUES(?,?,?,?,?)",
                       ("student1", "teacher1", "teacher", "Mathematics", api._utc_now()))
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


if __name__ == "__main__":
    unittest.main()
