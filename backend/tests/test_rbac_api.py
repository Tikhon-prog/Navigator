import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from fastapi import HTTPException

from backend import rbac_api, school_api as core, sso_api


class SchoolPositionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.db_patch = patch.object(core, "DB_PATH", Path(self.tmp.name) / "rbac.sqlite3")
        self.db_patch.start()
        self.secret_patch = patch.object(core, "TOKEN_SECRET", "unit-test-signing-secret-that-is-long-enough")
        self.secret_patch.start()
        self.env_patch = patch.dict(os.environ, {"NAVIGATOR_TOKEN_SECRET": "unit-test-signing-secret-that-is-long-enough"})
        self.env_patch.start()
        core.init_db()
        rbac_api._init()
        with core._db() as db:
            for uid, username, role, cls in [
                ("admin1", "admin", "admin", None),
                ("teacher1", "teacher", "teacher", "8A"),
                ("student1", "student1", "student", "8A"),
                ("student2", "student2", "student", "8B"),
            ]:
                db.execute(
                    "INSERT INTO users(id,username,password_hash,role,display_name,class_id,created_at) VALUES(?,?,?,?,?,?,?)",
                    (uid, username, core._hash_password("test password long enough"), role, username, cls, core._utc_now()),
                )
            db.execute(
                "INSERT INTO staff_positions(user_id,position,scope_class,assigned_by,updated_at) VALUES(?,?,?,?,?)",
                ("teacher1", "homeroom_teacher", "8A", "admin1", core._utc_now()),
            )

    def tearDown(self):
        self.env_patch.stop()
        self.secret_patch.stop()
        self.db_patch.stop()
        self.tmp.cleanup()

    def test_configured_bootstrap_creates_one_director_and_links_optional_sso_identity(self):
        env = {
            "POKOLENIE_BOOTSTRAP_DIRECTOR_USERNAME": "director.one",
            "POKOLENIE_BOOTSTRAP_DIRECTOR_PASSWORD": "director-bootstrap-password-42",
            "POKOLENIE_BOOTSTRAP_DIRECTOR_DISPLAY_NAME": "Директор школы",
            "NAVIGATOR_OIDC_ISSUER": "https://school-id.example.org",
            "POKOLENIE_BOOTSTRAP_DIRECTOR_SSO_SUBJECT": "school-subject-director-001",
        }
        with patch.dict(os.environ, env):
            sso_api.init_sso_tables()
            rbac_api._bootstrap_director()
            rbac_api._bootstrap_director()  # restarts must not create duplicates or reset credentials
        with core._db() as db:
            users = db.execute("SELECT id,username,role,display_name FROM users WHERE username='director.one'").fetchall()
            self.assertEqual(len(users), 1)
            self.assertEqual(users[0]["role"], "teacher")
            position = db.execute("SELECT position FROM staff_positions WHERE user_id=?", (users[0]["id"],)).fetchone()
            identity = db.execute("SELECT issuer,subject FROM sso_identities WHERE user_id=?", (users[0]["id"],)).fetchone()
        self.assertEqual(position["position"], "director")
        self.assertEqual(identity["issuer"], "https://school-id.example.org")
        self.assertEqual(identity["subject"], "school-subject-director-001")

    def test_director_bootstrap_requires_a_long_password(self):
        with patch.dict(os.environ, {
            "POKOLENIE_BOOTSTRAP_DIRECTOR_USERNAME": "director.one",
            "POKOLENIE_BOOTSTRAP_DIRECTOR_PASSWORD": "short",
            "POKOLENIE_BOOTSTRAP_DIRECTOR_SSO_SUBJECT": "",
        }):
            with self.assertRaises(RuntimeError):
                rbac_api._bootstrap_director()

    def test_bootstrap_does_not_replace_an_existing_director(self):
        with core._db() as db:
            db.execute(
                "INSERT INTO users(id,username,password_hash,role,display_name,created_at) VALUES(?,?,?,?,?,?)",
                ("existing-director", "director-existing", core._hash_password("existing-director-password-43"),
                 "teacher", "Existing Director", core._utc_now()),
            )
            db.execute(
                "INSERT INTO staff_positions(user_id,position,scope_class,assigned_by,updated_at) VALUES(?,?,?,?,?)",
                ("existing-director", "director", None, "admin1", core._utc_now()),
            )
        with patch.dict(os.environ, {
            "POKOLENIE_BOOTSTRAP_DIRECTOR_USERNAME": "different.director",
            "POKOLENIE_BOOTSTRAP_DIRECTOR_PASSWORD": "another-long-password-43",
            "POKOLENIE_BOOTSTRAP_DIRECTOR_SSO_SUBJECT": "",
        }):
            rbac_api._bootstrap_director()
        with core._db() as db:
            self.assertIsNone(db.execute("SELECT 1 FROM users WHERE username='different.director'").fetchone())

    def test_homeroom_teacher_sees_only_assigned_class(self):
        actor = {"id": "teacher1", "role": "teacher", "class_id": "8A"}
        result = rbac_api.management_students(actor)
        self.assertEqual([item["id"] for item in result["data"]], ["student1"])
        self.assertEqual(result["scope"], "8A")

    def test_teacher_cannot_read_school_wide_directory_without_position(self):
        with core._db() as db:
            db.execute("DELETE FROM staff_positions WHERE user_id='teacher1'")
        actor = {"id": "teacher1", "role": "teacher", "class_id": "8A"}
        result = rbac_api.management_students(actor)
        self.assertEqual(result["data"], [])

    def test_readiness_requires_authentication_and_nonempty_classes_and_schedule(self):
        with patch("backend.main.read_sheet", side_effect=lambda sheet: (
            [{"id": "8A", "name": "8A"}] if sheet == "Classes" else
            [{"class_id": "8A", "subject": "Math"}] if sheet == "BaseSchedule" else []
        )):
            self.assertEqual(rbac_api.readiness()["status"], "ready")
        with patch("backend.main.read_sheet", side_effect=lambda sheet: (
            [{"id": "8A", "name": "8A"}] if sheet == "Classes" else []
        )):
            with self.assertRaises(HTTPException) as raised:
                rbac_api.readiness()
            self.assertEqual(raised.exception.status_code, 503)

    def test_password_reset_revokes_refresh_tokens_and_registered_devices(self):
        with core._db() as db:
            user = db.execute("SELECT * FROM users WHERE id='student1'").fetchone()
            db.execute(
                "UPDATE staff_positions SET position='director',scope_class=NULL WHERE user_id='teacher1'"
            )
            db.execute(
                "INSERT INTO devices(id,user_id,fcm_token,platform,active,updated_at) VALUES(?,?,?,?,1,?)",
                ("reset-device", "student1", "reset-device-token-000000000001", "android", core._utc_now()),
            )
        session = core._issue_session(user)
        result = rbac_api.reset_user_password(
            "student1",
            rbac_api.PasswordResetBody(password="new-reset-password-long-enough"),
            {"id": "teacher1", "role": "teacher"},
        )
        self.assertEqual(result["status"], "password_reset")
        with core._db() as db:
            after = db.execute("SELECT token_version FROM users WHERE id='student1'").fetchone()
            refresh = db.execute("SELECT revoked_at FROM refresh_tokens WHERE token_hash=?",
                                  (__import__("hashlib").sha256(session["refresh_token"].encode()).hexdigest(),)).fetchone()
            device = db.execute("SELECT active FROM devices WHERE id='reset-device'").fetchone()
        self.assertEqual(after["token_version"], 1)
        self.assertIsNotNone(refresh["revoked_at"])
        self.assertEqual(device["active"], 0)

    def test_director_cannot_reset_technical_admin_password(self):
        with self.assertRaises(HTTPException) as raised:
            rbac_api.reset_user_password(
                "admin1",
                rbac_api.PasswordResetBody(password="new-reset-password-long-enough"),
                {"id": "teacher1", "role": "teacher"},
            )
        self.assertEqual(raised.exception.status_code, 403)

    def test_class_labels_normalize_cyrillic_and_latin_lookalikes(self):
        self.assertEqual(core.normalize_class_id("8А"), core.normalize_class_id("8A"))
        self.assertEqual(core.normalize_class_id(" 10-Б "), core.normalize_class_id("10-B"))

    def test_teacher_account_cannot_receive_mentor_only_position(self):
        with self.assertRaises(HTTPException) as raised:
            rbac_api.assign_position(
                rbac_api.PositionBody(username="teacher", position="mentor"),
                {"id": "admin1", "role": "admin"},
            )
        self.assertEqual(raised.exception.status_code, 422)

    def test_mentor_account_can_receive_mentor_coordinator_position(self):
        with core._db() as db:
            db.execute(
                "INSERT INTO users(id,username,password_hash,role,display_name,created_at) VALUES(?,?,?,?,?,?)",
                ("mentor1", "mentor.one", core._hash_password("test password long enough"), "mentor", "Mentor One", core._utc_now()),
            )
        result = rbac_api.assign_position(
            rbac_api.PositionBody(username="mentor.one", position="mentor_coordinator"),
            {"id": "admin1", "role": "admin"},
        )
        self.assertEqual(result["position"], "mentor_coordinator")
        self.assertTrue(rbac_api._has({"id": "mentor1", "role": "mentor"}, "assignments.manage"))

    def test_deputy_can_manage_operational_staff_but_not_administer_the_system(self):
        deputy = {"id": "deputy1", "role": "teacher"}
        with patch("backend.rbac_api._position", return_value=("deputy", None)):
            self.assertTrue(rbac_api._has(deputy, "staff.manage"))
            self.assertTrue(rbac_api._has(deputy, "assignments.manage"))
            self.assertFalse(rbac_api._has(deputy, "*"))

    def test_position_permission_is_not_equivalent_to_admin(self):
        actor = {"id": "teacher1", "role": "teacher", "class_id": "8A"}
        self.assertTrue(rbac_api._has(actor, "students.read_class"))
        self.assertFalse(rbac_api._has(actor, "staff.manage"))
        self.assertTrue(rbac_api._has({"id": "admin1", "role": "admin"}, "staff.manage"))


if __name__ == "__main__":
    unittest.main()
