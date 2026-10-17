import unittest
from unittest.mock import patch

from backend import main


class PublicAnnouncementVisibilityTests(unittest.TestCase):
    def setUp(self):
        self.rows = [
            {"id": "global", "title": "Для всех", "target_class_id": "", "published_at": "2026-10-17"},
            {"id": "class_8a", "title": "Для 8А", "target_class_id": "8A", "published_at": "2026-10-16"},
            {"id": "class_8b", "title": "Для 8Б", "target_class_id": "8B", "published_at": "2026-10-15"},
        ]
        self.source = patch.object(main, "read_sheet", return_value=self.rows)
        self.source.start()

    def tearDown(self):
        self.source.stop()

    def test_anonymous_client_sees_only_school_wide_notices(self):
        result = main.get_announcements()
        self.assertEqual([item["id"] for item in result["data"]], ["global"])

    def test_class_filter_returns_school_wide_and_matching_class(self):
        result = main.get_announcements("8А")
        self.assertEqual({item["id"] for item in result["data"]}, {"global", "class_8a"})

    def test_generic_announcements_endpoint_uses_same_filter(self):
        result = main.get_sheet_data("Announcements")
        self.assertEqual([item["id"] for item in result["data"]], ["global"])

    def test_private_sheets_are_still_not_available(self):
        from fastapi import HTTPException
        with self.assertRaises(HTTPException):
            main.get_sheet_data("Admins")


if __name__ == "__main__":
    unittest.main()
