import json
import os
import unittest

from fastapi.testclient import TestClient

from backend.server_app import create_app


class NavigatorServerApiTests(unittest.TestCase):
    def setUp(self):
        self.app = create_app(
            database_url="sqlite://",
            jwt_secret="test-secret-that-is-long-enough-for-hmac-256",
            bootstrap_admin_key="bootstrap-key-for-tests",
        )
        self.client = TestClient(self.app)
        response = self.client.post("/api/v1/auth/bootstrap", json={
            "bootstrap_key": "bootstrap-key-for-tests",
            "login": "root-admin",
            "password": "very-long-admin-password-123",
            "display_name": "School Admin",
        })
        self.assertEqual(response.status_code, 201, response.text)
        self.admin = response.json()
        self.admin_headers = {"Authorization": f"Bearer {self.admin['access_token']}"}

    def tearDown(self):
        self.client.close()

    def create_user(self, login, role, name=None):
        response = self.client.post("/api/v1/admin/users", headers=self.admin_headers, json={
            "login": login,
            "password": "very-long-test-password-123",
            "display_name": name or login,
            "role": role,
        })
        self.assertEqual(response.status_code, 201, response.text)
        return response.json()

    def token_for(self, login):
        response = self.client.post("/api/v1/auth/login", json={
            "login": login,
            "password": "very-long-test-password-123",
        })
        self.assertEqual(response.status_code, 200, response.text)
        return {"Authorization": f"Bearer {response.json()['access_token']}"}

    def set_up_school_graph(self):
        mentor = self.create_user("mentor-one", "mentor", "Mentor One")
        other_mentor = self.create_user("mentor-two", "mentor", "Mentor Two")
        teacher = self.create_user("teacher-one", "teacher", "Teacher One")
        student = self.create_user("student-one", "student", "Student One")
        stranger = self.create_user("student-two", "student", "Student Two")

        self.assertEqual(self.client.post("/api/v1/admin/classes", headers=self.admin_headers,
            json={"id": "8A", "name": "8А", "grade": "8"}).status_code, 201)
        for class_id in ("8A", "8B"):
            if class_id == "8B":
                self.client.post("/api/v1/admin/classes", headers=self.admin_headers,
                    json={"id": "8B", "name": "8Б", "grade": "8"})
        self.client.post("/api/v1/admin/assignments/mentor", headers=self.admin_headers,
            json={"mentor_id": mentor["id"], "student_id": student["id"]})
        self.client.post("/api/v1/admin/assignments/teacher", headers=self.admin_headers,
            json={"teacher_id": teacher["id"], "class_id": "8A"})
        self.client.post("/api/v1/admin/class-memberships", headers=self.admin_headers,
            json={"student_id": student["id"], "class_id": "8A"})
        self.client.post("/api/v1/admin/class-memberships", headers=self.admin_headers,
            json={"student_id": stranger["id"], "class_id": "8B"})
        return mentor, other_mentor, teacher, student, stranger

    def test_bootstrap_is_disabled_after_the_first_administrator(self):
        response = self.client.post("/api/v1/auth/bootstrap", json={
            "bootstrap_key": "bootstrap-key-for-tests",
            "login": "second-root",
            "password": "another-long-password-123",
            "display_name": "Second Admin",
        })
        self.assertEqual(response.status_code, 409)

    def test_bootstrap_rejects_a_wrong_secret(self):
        app = create_app(database_url="sqlite://", jwt_secret="another-test-secret-at-least-32-chars")
        client = TestClient(app)
        try:
            response = client.post("/api/v1/auth/bootstrap", json={
                "bootstrap_key": "guess",
                "login": "admin-one",
                "password": "a-long-password-12345",
                "display_name": "Admin",
            })
            self.assertEqual(response.status_code, 403)
        finally:
            client.close()

    def test_private_endpoints_require_authentication(self):
        response = self.client.get("/api/v1/mentees")
        self.assertEqual(response.status_code, 401)

    def test_mentor_can_see_only_assigned_mentees_and_their_supplements(self):
        mentor, other_mentor, _teacher, student, stranger = self.set_up_school_graph()
        created = self.client.post("/api/v1/admin/supplements", headers=self.admin_headers, json={
            "student_id": student["id"], "title": "Робототехника", "weekday": 3,
            "start_time": "15:00", "end_time": "16:30", "teacher_name": "Teacher",
            "room": "317",
        })
        self.assertEqual(created.status_code, 201, created.text)
        lesson = self.client.post("/api/v1/admin/schedule", headers=self.admin_headers, json={
            "class_id": "8A", "weekday": 3, "lesson_number": 2,
            "start_time": "10:00", "subject": "Информатика", "room": "311",
        })
        self.assertEqual(lesson.status_code, 201, lesson.text)

        mentor_headers = self.token_for("mentor-one")
        mentees = self.client.get("/api/v1/mentees", headers=mentor_headers)
        self.assertEqual(mentees.status_code, 200, mentees.text)
        self.assertEqual([x["student"]["id"] for x in mentees.json()["data"]], [student["id"]])
        self.assertEqual(mentees.json()["data"][0]["supplements"][0]["title"], "Робототехника")
        self.assertEqual(mentees.json()["data"][0]["schedule"][0]["subject"], "Информатика")

        forbidden = self.client.get(
            f"/api/v1/students/{stranger['id']}/supplements", headers=mentor_headers
        )
        self.assertEqual(forbidden.status_code, 403)

        self.assertEqual(self.client.get("/api/v1/mentees",
            headers=self.token_for("mentor-two")).json()["data"], [])

    def test_teacher_can_read_only_students_from_assigned_classes(self):
        _mentor, _other_mentor, teacher, student, stranger = self.set_up_school_graph()
        headers = self.token_for("teacher-one")
        response = self.client.get("/api/v1/students", headers=headers)
        self.assertEqual(response.status_code, 200)
        self.assertEqual([x["id"] for x in response.json()["data"]], [student["id"]])
        filtered = self.client.get("/api/v1/students?class_id=8A", headers=headers)
        self.assertEqual(filtered.status_code, 200, filtered.text)
        self.assertEqual([x["id"] for x in filtered.json()["data"]], [student["id"]])
        forbidden_class = self.client.get("/api/v1/students?class_id=8B", headers=headers)
        self.assertEqual(forbidden_class.status_code, 403)
        self.assertEqual(self.client.get(f"/api/v1/students/{stranger['id']}/schedule",
            headers=headers).status_code, 403)

    def test_student_can_read_own_records_but_not_other_students(self):
        _mentor, _other_mentor, _teacher, student, stranger = self.set_up_school_graph()
        self.client.post("/api/v1/admin/supplements", headers=self.admin_headers, json={
            "student_id": student["id"], "title": "Шахматы", "weekday": 2,
            "start_time": "14:00",
        })
        student_headers = self.token_for("student-one")
        self.assertEqual(self.client.get(f"/api/v1/students/{student['id']}/supplements",
            headers=student_headers).status_code, 200)
        self.assertEqual(self.client.get(f"/api/v1/students/{stranger['id']}/supplements",
            headers=student_headers).status_code, 403)

    def test_critical_alert_is_saved_even_without_firebase_and_is_targeted(self):
        mentor, _other_mentor, _teacher, student, _stranger = self.set_up_school_graph()
        response = self.client.post("/api/v1/alerts", headers=self.admin_headers, json={
            "title": "Тестовая тревога", "body": "Учебная проверка, это не настоящая тревога.",
            "severity": "critical", "target_type": "all",
        })
        self.assertEqual(response.status_code, 201, response.text)
        payload = response.json()
        self.assertEqual(payload["severity"], "critical")
        self.assertEqual(payload["delivery"]["status"], "not_configured")
        self.assertEqual(self.client.get("/api/v1/alerts",
            headers=self.token_for("student-one")).json()["data"][0]["id"], payload["id"])
        self.assertEqual(self.client.get("/api/v1/alerts",
            headers=self.token_for("mentor-one")).json()["data"][0]["id"], payload["id"])

    def test_only_admin_or_emergency_manager_can_send_school_alerts(self):
        self.create_user("a-student", "student")
        headers = self.token_for("a-student")
        response = self.client.post("/api/v1/alerts", headers=headers, json={
            "title": "No", "body": "Must be forbidden",
        })
        self.assertEqual(response.status_code, 403)

    def test_unknown_roles_and_bad_memberships_are_rejected(self):
        response = self.client.post("/api/v1/admin/users", headers=self.admin_headers, json={
            "login": "hacker", "password": "very-long-password-123",
            "display_name": "Hacker", "role": "superuser",
        })
        self.assertEqual(response.status_code, 422)
        bad = self.client.post("/api/v1/admin/class-memberships", headers=self.admin_headers, json={
            "student_id": "missing-user", "class_id": "missing-class",
        })
        self.assertEqual(bad.status_code, 422)

    def test_health_reports_database_and_optional_push_status(self):
        response = self.client.get("/api/v1/health")
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json()["database"], "ok")



    def test_teacher_can_read_assigned_class_schedule_only(self):
        _mentor, _other_mentor, _teacher, _student, _stranger = self.set_up_school_graph()
        lesson = self.client.post("/api/v1/admin/schedule", headers=self.admin_headers, json={
            "class_id": "8A", "weekday": 1, "lesson_number": 1,
            "start_time": "08:30", "subject": "Алгебра", "room": "311",
        })
        self.assertEqual(lesson.status_code, 201, lesson.text)
        teacher_headers = self.token_for("teacher-one")
        visible = self.client.get("/api/v1/classes/8A/schedule", headers=teacher_headers)
        self.assertEqual(visible.status_code, 200, visible.text)
        self.assertEqual(visible.json()["data"][0]["subject"], "Алгебра")
        forbidden = self.client.get("/api/v1/classes/8B/schedule", headers=teacher_headers)
        self.assertEqual(forbidden.status_code, 403)

    def test_admin_can_edit_schedule_and_supplement_and_cannot_disable_last_admin(self):
        _mentor, _other_mentor, _teacher, student, _stranger = self.set_up_school_graph()
        lesson = self.client.post("/api/v1/admin/schedule", headers=self.admin_headers, json={
            "class_id": "8A", "weekday": 1, "lesson_number": 1,
            "start_time": "08:30", "subject": "Алгебра", "room": "311",
        })
        self.assertEqual(lesson.status_code, 201, lesson.text)
        lesson_id = lesson.json()["id"]
        updated_lesson = self.client.patch(
            f"/api/v1/admin/schedule/{lesson_id}", headers=self.admin_headers,
            json={"subject": "Геометрия", "room": "312"},
        )
        self.assertEqual(updated_lesson.status_code, 200, updated_lesson.text)
        self.assertEqual(updated_lesson.json()["subject"], "Геометрия")
        self.assertEqual(updated_lesson.json()["room"], "312")
        deleted_lesson = self.client.delete(
            f"/api/v1/admin/schedule/{lesson_id}", headers=self.admin_headers
        )
        self.assertEqual(deleted_lesson.status_code, 204)

        supplement = self.client.post("/api/v1/admin/supplements", headers=self.admin_headers, json={
            "student_id": student["id"], "title": "Робототехника", "weekday": 3,
            "start_time": "15:00", "room": "317",
        })
        self.assertEqual(supplement.status_code, 201, supplement.text)
        supplement_id = supplement.json()["id"]
        updated_supplement = self.client.patch(
            f"/api/v1/admin/supplements/{supplement_id}", headers=self.admin_headers,
            json={"room": "318", "teacher_name": "New teacher"},
        )
        self.assertEqual(updated_supplement.status_code, 200, updated_supplement.text)
        self.assertEqual(updated_supplement.json()["room"], "318")
        self.assertEqual(updated_supplement.json()["teacher_name"], "New teacher")
        self.assertEqual(self.client.delete(
            f"/api/v1/admin/supplements/{supplement_id}", headers=self.admin_headers
        ).status_code, 204)

        locked_out = self.client.patch(
            f"/api/v1/admin/users/{self.admin['user']['id']}",
            headers=self.admin_headers, json={"active": False},
        )
        self.assertEqual(locked_out.status_code, 409)

    def test_admin_can_update_account_details_without_exposing_password_hash(self):
        created = self.create_user("teacher-edit", "teacher", "Old Name")
        response = self.client.patch(
            f"/api/v1/admin/users/{created['id']}", headers=self.admin_headers,
            json={"display_name": "Updated Name", "active": False},
        )
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json()["display_name"], "Updated Name")
        self.assertFalse(response.json()["active"])
        self.assertNotIn("password_hash", response.json())
        self.assertEqual(self.client.get("/api/v1/admin/users",
            headers=self.admin_headers).status_code, 200)

if __name__ == "__main__":
    unittest.main()
