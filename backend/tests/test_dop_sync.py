import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from backend import main, rbac_api, school_api as core


class DOPSyncReconciliationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.db_patch = patch.object(core, "DB_PATH", Path(self.tmp.name) / "dop-sync.sqlite3")
        self.db_patch.start()
        self.secret_patch = patch.object(core, "TOKEN_SECRET", "dop-sync-test-secret-at-least-32-bytes")
        self.secret_patch.start()
        self.env_patch = patch.dict(os.environ, {
            "NAVIGATOR_TOKEN_SECRET": "dop-sync-test-secret-at-least-32-bytes",
            "NAVIGATOR_DATA_SOURCE": "json",
        })
        self.env_patch.start()
        core.init_db()
        rbac_api._init()
        with core._db() as db:
            db.execute(
                "INSERT INTO users(id,username,password_hash,role,display_name,class_id,created_at) VALUES(?,?,?,?,?,?,?)",
                ("admin1", "admin", core._hash_password("test password long enough"), "admin", "Admin", None, core._utc_now()),
            )
            db.execute(
                "INSERT INTO users(id,username,password_hash,role,display_name,class_id,created_at) VALUES(?,?,?,?,?,?,?)",
                ("student1", "student.one", core._hash_password("test password long enough"), "student", "Student One", "8A", core._utc_now()),
            )
            db.execute(
                "INSERT INTO student_supplements(id,student_id,title,weekday,time,teacher,room,status,updated_at,source_key) "
                "VALUES(?,?,?,?,?,?,?,?,?,?)",
                ("old-dop", "student1", "Old robotics", 2, "15:00", "Teacher", "317", "active", core._utc_now(), "workbook:student1:id:old"),
            )

    def tearDown(self):
        self.env_patch.stop()
        self.secret_patch.stop()
        self.db_patch.stop()
        self.tmp.cleanup()

    def test_complete_nonempty_sync_deactivates_stale_workbook_records(self):
        rows = [{
            "student_id": "student1", "id": "current", "title": "Current robotics",
            "weekday": 3, "time": "15:30", "teacher": "Teacher", "room": "317",
        }]
        with patch.object(main, "read_sheet", return_value=rows):
            result = rbac_api.sync_supplements({"id": "admin1", "role": "admin"})
        self.assertEqual(result["status"], "completed")
        self.assertEqual(result["deactivated"], 1)
        with core._db() as db:
            stale = db.execute("SELECT status FROM student_supplements WHERE id='old-dop'").fetchone()
        self.assertEqual(stale["status"], "inactive")

    def test_empty_source_preserves_existing_active_records(self):
        with patch.object(main, "read_sheet", return_value=[]):
            result = rbac_api.sync_supplements({"id": "admin1", "role": "admin"})
        self.assertEqual(result["status"], "partial_preserved_previous")
        with core._db() as db:
            stale = db.execute("SELECT status FROM student_supplements WHERE id='old-dop'").fetchone()
        self.assertEqual(stale["status"], "active")


if __name__ == "__main__":
    unittest.main()
