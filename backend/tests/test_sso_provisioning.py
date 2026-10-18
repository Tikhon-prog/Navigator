import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from backend import rbac_api, school_api as core, sso_api


class SsoProvisioningTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.db_patch = patch.object(core, "DB_PATH", Path(self.tmp.name) / "sso.sqlite3")
        self.db_patch.start()
        self.secret_patch = patch.object(core, "TOKEN_SECRET", "unit-test-signing-secret-that-is-long-enough")
        self.secret_patch.start()
        self.env_patch = patch.dict(os.environ, {
            "NAVIGATOR_TOKEN_SECRET": "unit-test-signing-secret-that-is-long-enough",
            "NAVIGATOR_OIDC_USERNAME_CLAIM": "preferred_username",
            "NAVIGATOR_OIDC_ROLE_CLAIM": "role",
            "NAVIGATOR_OIDC_CLASS_CLAIM": "class_id",
            "NAVIGATOR_OIDC_DISPLAY_NAME_CLAIM": "name",
            "NAVIGATOR_OIDC_AUTO_LINK_USERNAME": "false",
            "NAVIGATOR_OIDC_AUTO_PROVISION": "true",
            "NAVIGATOR_OIDC_ALLOW_ADMIN_PROVISION": "false",
        })
        self.env_patch.start()
        core.init_db()
        sso_api.init_sso_tables()
        rbac_api._init()

    def tearDown(self):
        self.env_patch.stop()
        self.secret_patch.stop()
        self.db_patch.stop()
        self.tmp.cleanup()


    def test_secure_service_url_allows_https_and_exact_loopback_only(self):
        self.assertTrue(sso_api._is_secure_service_url("https://idp.school.example"))
        self.assertTrue(sso_api._is_secure_service_url("http://localhost:8080"))
        self.assertTrue(sso_api._is_secure_service_url("http://127.0.0.1:8080"))
        self.assertTrue(sso_api._is_secure_service_url("http://[::1]:8080"))
        self.assertFalse(sso_api._is_secure_service_url("http://localhost.attacker.example"))
        self.assertFalse(sso_api._is_secure_service_url("http://127.0.0.1.attacker.example"))
        self.assertFalse(sso_api._is_secure_service_url("http://localhost:not-a-port"))
        self.assertFalse(sso_api._is_secure_service_url("https://idp.school.example:99999"))
        self.assertFalse(sso_api._is_secure_service_url("http://10.0.0.1"))
        self.assertFalse(sso_api._is_secure_service_url("https://"))

    def test_director_bootstrap_preserves_exact_issuer_with_trailing_slash(self):
        env = {
            "POKOLENIE_BOOTSTRAP_DIRECTOR_USERNAME": "director.slash",
            "POKOLENIE_BOOTSTRAP_DIRECTOR_PASSWORD": "director-bootstrap-password-44",
            "NAVIGATOR_OIDC_ISSUER": "https://school-id.example.org/",
            "POKOLENIE_BOOTSTRAP_DIRECTOR_SSO_SUBJECT": "school-subject-director-slash",
        }
        with patch.dict(os.environ, env):
            rbac_api._bootstrap_director()
        with core._db() as db:
            identity = db.execute(
                "SELECT issuer,subject FROM sso_identities WHERE subject=?",
                ("school-subject-director-slash",),
            ).fetchone()
        self.assertEqual(identity["issuer"], "https://school-id.example.org/")

    def test_authoritative_student_claim_provisions_class_scoped_account(self):
        user = sso_api._link_or_provision({
            "sub": "school-sub-001", "preferred_username": "student.001",
            "role": "student", "class_id": "8A", "name": "Student One",
        }, "https://idp.school.example")
        self.assertIsNotNone(user)
        self.assertEqual(user["role"], "student")
        self.assertEqual(user["class_id"], "8A")
        with core._db() as db:
            identity = db.execute("SELECT user_id FROM sso_identities WHERE subject='school-sub-001'").fetchone()
        self.assertEqual(identity["user_id"], user["id"])

    def test_mentor_coordinator_uses_teacher_base_role_and_separate_position(self):
        user = sso_api._link_or_provision({
            "sub": "mentor-coord-sub", "preferred_username": "mentor.coordinator",
            "role": "mentor_coordinator", "name": "Mentor Coordinator",
        }, "https://idp.school.example")
        self.assertIsNotNone(user)
        self.assertEqual(user["role"], "teacher")
        with core._db() as db:
            position = db.execute(
                "SELECT position FROM staff_positions WHERE user_id=?", (user["id"],)
            ).fetchone()
        self.assertEqual(position["position"], "mentor_coordinator")

    def test_dop_coordinator_is_provisioned_with_valid_base_role(self):
        user = sso_api._link_or_provision({
            "sub": "school-dop-coordinator-001", "preferred_username": "dop.coordinator",
            "role": "dop_coordinator", "name": "DOP Coordinator",
        }, "https://idp.school.example")
        self.assertIsNotNone(user)
        self.assertEqual(user["role"], "teacher")
        with core._db() as db:
            position = db.execute("SELECT position FROM staff_positions WHERE user_id=?", (user["id"],)).fetchone()
        self.assertEqual(position["position"], "dop_coordinator")

    def test_admin_auto_provision_is_disabled_by_default(self):
        user = sso_api._link_or_provision({
            "sub": "school-admin-001", "preferred_username": "new.admin",
            "role": "admin", "name": "New Admin",
        }, "https://idp.school.example")
        self.assertIsNone(user)

    def test_username_auto_link_does_not_upgrade_mismatched_role(self):
        with core._db() as db:
            db.execute(
                "INSERT INTO users(id,username,password_hash,role,display_name,class_id,created_at) VALUES(?,?,?,?,?,?,?)",
                ("student1", "existing.student", core._hash_password("a sufficiently long test password"),
                 "student", "Existing Student", "8A", core._utc_now()),
            )
        with patch.dict(os.environ, {"NAVIGATOR_OIDC_AUTO_LINK_USERNAME": "true"}):
            user = sso_api._link_or_provision({
                "sub": "different-sub", "preferred_username": "existing.student",
                "role": "teacher", "class_id": "8A", "name": "Existing Student",
            }, "https://idp.school.example")
        self.assertIsNone(user)
        with core._db() as db:
            count = db.execute("SELECT COUNT(*) AS n FROM sso_identities").fetchone()["n"]
        self.assertEqual(count, 0)


if __name__ == "__main__":
    unittest.main()
