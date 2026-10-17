import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from fastapi import HTTPException

from backend import rbac_api, school_api as core


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

    def test_position_permission_is_not_equivalent_to_admin(self):
        actor = {"id": "teacher1", "role": "teacher", "class_id": "8A"}
        self.assertTrue(rbac_api._has(actor, "students.read_class"))
        self.assertFalse(rbac_api._has(actor, "staff.manage"))
        self.assertTrue(rbac_api._has({"id": "admin1", "role": "admin"}, "staff.manage"))


if __name__ == "__main__":
    unittest.main()
