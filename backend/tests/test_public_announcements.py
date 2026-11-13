import unittest
from unittest.mock import patch

from backend import main, rbac_api


class PublicAnnouncementVisibilityTests(unittest.TestCase):
    def setUp(self):
        self.rows = [
            {"id": "global", "title": "Для всех", "target_class_id": "", "published_at": "2026-10-17"},
            {"id": "class_8a", "title": "Для 8А", "target_class_id": "8A", "published_at": "2026-10-16"},
            {"id": "class_8b", "title": "Для 8Б", "target_class_id": "8Б", "published_at": "2026-10-15"},
            {"id": "class_8v", "title": "Для 8В", "target_class_id": "8В", "published_at": "2026-10-14"},
        ]
        self.source = patch.object(main, "read_sheet", return_value=self.rows)
        self.source.start()

    def tearDown(self):
        self.source.stop()

    def test_anonymous_client_sees_only_school_wide_notices(self):
        result = main.get_announcements()
        self.assertEqual([item["id"] for item in result["data"]], ["global"])

    def test_public_class_filter_never_reveals_class_targeted_notices(self):
        result = main.get_announcements("8А")
        self.assertEqual([item["id"] for item in result["data"]], ["global"])

    def test_authenticated_workbook_feed_returns_matching_class_notices(self):
        result = rbac_api.list_workbook_announcements({"id": "student1", "role": "student", "class_id": "8А"})
        self.assertEqual({item["id"] for item in result["data"]}, {"global", "class_8a"})

    def test_neighbouring_parallels_do_not_see_each_others_notices(self):
        feed_b = rbac_api.list_workbook_announcements({"id": "s2", "role": "student", "class_id": "8Б"})
        self.assertEqual({item["id"] for item in feed_b["data"]}, {"global", "class_8b"})
        feed_v = rbac_api.list_workbook_announcements({"id": "s3", "role": "student", "class_id": "8В"})
        self.assertEqual({item["id"] for item in feed_v["data"]}, {"global", "class_8v"})

    def test_generic_announcements_endpoint_uses_same_filter(self):
        result = main.get_sheet_data("Announcements")
        self.assertEqual([item["id"] for item in result["data"]], ["global"])

    def test_private_sheets_are_still_not_available(self):
        from fastapi import HTTPException
        with self.assertRaises(HTTPException):
            main.get_sheet_data("Admins")


if __name__ == "__main__":
    unittest.main()
