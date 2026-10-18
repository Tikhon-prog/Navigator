import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from backend import main, rbac_api, school_api as core


class TeacherAssignmentSyncTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.db_patch = patch.object(core, "DB_PATH", Path(self.tmp.name) / "sync.sqlite3")
        self.db_patch.start()
        self.secret_patch = patch.object(core, "TOKEN_SECRET", "teacher-sync-test-secret-at-least-32-bytes")
        self.secret_patch.start()
        self.env_patch = patch.dict(os.environ, {
            "NAVIGATOR_TOKEN_SECRET": "teacher-sync-test-secret-at-least-32-bytes",
            "NAVIGATOR_DATA_SOURCE": "json",
            "NAVIGATOR_BOOTSTRAP_ADMIN_USERNAME": "",
            "NAVIGATOR_BOOTSTRAP_ADMIN_PASSWORD": "",
        })
        self.env_patch.start()
        core.init_db()
        rbac_api._init()
        with core._db() as db:
            accounts = [
                ("admin1", "admin", "admin", "School Admin", None),
                ("teacher1", "teacher.one", "teacher", "Teacher One", "8A"),
                ("teacher2", "teacher.two", "teacher", "Teacher Two", "8A"),
                ("student1", "student.one", "student", "Student One", "8A"),
                ("student2", "student.two", "student", "Student Two", "8А"),
                ("student3", "student.three", "student", "Student Three", "8B"),
            ]
            for uid, username, role, name, class_id in accounts:
                db.execute(
                    "INSERT INTO users(id,username,password_hash,role,display_name,class_id,created_at) "
                    "VALUES(?,?,?,?,?,?,?)",
                    (uid, username, core._hash_password("test password safely long enough"), role, name, class_id, core._utc_now()),
                )
            # Old timetable-derived access plus a separate manual relationship.
            db.execute(
                "INSERT INTO teacher_subject_assignments(student_id,staff_id,subject,created_at,source_key) VALUES(?,?,?,?,?)",
                ("student1", "teacher1", "Mathematics", core._utc_now(), "schedule:old-math"),
            )
            db.execute(
                "INSERT INTO teacher_subject_assignments(student_id,staff_id,subject,created_at,source_key) VALUES(?,?,?,?,?)",
                ("student1", "teacher2", "Mathematics", core._utc_now(), None),
            )

    def tearDown(self):
        self.env_patch.stop()
        self.secret_patch.stop()
        self.db_patch.stop()
        self.tmp.cleanup()

    def _run_sync(self, rows):
        def source(sheet_name):
            if sheet_name == "Classes":
                return [{"id": "class8a", "name": "8A"}, {"id": "class8b", "name": "8B"}]
            if sheet_name == "BaseSchedule":
                return rows
            raise AssertionError(f"Unexpected sheet: {sheet_name}")

        with patch.object(main, "read_sheet", side_effect=source):
            return rbac_api.sync_teacher_assignments({"id": "admin1", "role": "admin"})

    def test_split_group_subject_does_not_auto_assign_every_student_to_both_teachers(self):
        rows = [
            {"class_id": "class8a", "class_name": "8A", "subject": "Mathematics",
             "weekday": 1, "time": "08:30", "group": 1, "teacher": "Teacher One"},
            {"class_id": "class8a", "class_name": "8A", "subject": "Mathematics",
             "weekday": 1, "time": "08:30", "group": 2, "teacher": "Teacher Two"},
        ]
        result = self._run_sync(rows)
        self.assertEqual(result["split_subjects"], 1)
        with core._db() as db:
            schedule_links = db.execute(
                "SELECT student_id,staff_id,source_key FROM teacher_subject_assignments "
                "WHERE subject='Mathematics' AND source_key LIKE 'schedule:%'"
            ).fetchall()
            manual_links = db.execute(
                "SELECT student_id,staff_id FROM teacher_subject_assignments "
                "WHERE subject='Mathematics' AND source_key IS NULL"
            ).fetchall()
        self.assertEqual(schedule_links, [])
        self.assertEqual([(row["student_id"], row["staff_id"]) for row in manual_links], [("student1", "teacher2")])

    def test_split_groups_across_different_days_are_not_auto_expanded_to_whole_class(self):
        rows = [
            {"class_id": "class8a", "class_name": "8A", "subject": "English",
             "weekday": 1, "time": "08:30", "group": 1, "teacher": "Teacher One"},
            {"class_id": "class8a", "class_name": "8A", "subject": "English",
             "weekday": 3, "time": "09:30", "group": 2, "teacher": "Teacher Two"},
        ]
        result = self._run_sync(rows)
        self.assertEqual(result["split_subjects"], 1)
        with core._db() as db:
            schedule_links = db.execute(
                "SELECT 1 FROM teacher_subject_assignments WHERE subject='English' AND source_key LIKE 'schedule:%'"
            ).fetchall()
        self.assertEqual(schedule_links, [])

    def test_incomplete_source_preserves_previous_schedule_assignments(self):
        rows = [
            {"class_id": "class8a", "class_name": "8A", "subject": "English",
             "weekday": 1, "time": "09:30", "group": 1, "teacher": "Teacher One"},
            {"class_id": "class8a", "class_name": "8A", "subject": "Physics",
             "weekday": 1, "time": "10:30", "group": 1, "teacher": "Unmapped Guest"},
        ]
        result = self._run_sync(rows)
        self.assertEqual(result["status"], "partial_preserved_previous")
        self.assertGreater(result["skipped"], 0)
        with core._db() as db:
            old = db.execute(
                "SELECT 1 FROM teacher_subject_assignments WHERE student_id='student1' "
                "AND staff_id='teacher1' AND subject='Mathematics' AND source_key='schedule:old-math'"
            ).fetchone()
            new = db.execute(
                "SELECT 1 FROM teacher_subject_assignments WHERE student_id='student1' "
                "AND staff_id='teacher1' AND subject='English'"
            ).fetchone()
        self.assertIsNotNone(old)
        self.assertIsNotNone(new)


if __name__ == "__main__":
    unittest.main()
