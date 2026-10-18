import os
import unittest
from unittest.mock import patch

from fastapi import HTTPException

from backend import main
from backend import school_api


class SchoolAuthConfigurationTests(unittest.TestCase):
    def test_placeholder_signing_secret_is_rejected(self):
        candidates = [
            "REPLACE_WITH_RANDOM_SECRET_AT_LEAST_32_CHARS",
            "example-secret-that-is-long-enough-but-not-real",
            "short",
        ]
        for secret in candidates:
            with self.subTest(secret=secret):
                with patch.object(school_api, "TOKEN_SECRET", secret):
                    with self.assertRaises(HTTPException) as raised:
                        school_api._signing_key()
                    self.assertEqual(raised.exception.status_code, 503)

    def test_long_random_looking_signing_secret_is_accepted(self):
        secret = "6f0a9c2e84b713d5f091ac67e3280d5d71c09b4a88e1c7f3"
        with patch.object(school_api, "TOKEN_SECRET", secret):
            self.assertEqual(school_api._signing_key(), secret.encode("utf-8"))


class BackendAccessTests(unittest.TestCase):
    def test_generic_endpoint_rejects_private_collections_without_reading_source(self):
        for name in ("Admins", "AuditLog", "Devices", "Settings", "Supplements"):
            with self.subTest(name=name):
                with patch.object(main, "read_sheet") as read_sheet:
                    with self.assertRaises(HTTPException) as raised:
                        main.get_sheet_data(name)
                    self.assertEqual(raised.exception.status_code, 404)
                    read_sheet.assert_not_called()

    def test_schema_rejects_private_collection_before_source_access(self):
        with patch.object(main, "load_configured_sheet") as read_source:
            with self.assertRaises(HTTPException) as raised:
                main.get_schema("Admins")
            self.assertEqual(raised.exception.status_code, 404)
            read_source.assert_not_called()

    def test_low_level_reader_rejects_private_collection_before_source_access(self):
        with patch.object(main, "load_configured_sheet") as read_source:
            with self.assertRaises(HTTPException) as raised:
                main.read_sheet("Admins")
            self.assertEqual(raised.exception.status_code, 404)
            read_source.assert_not_called()

    def test_public_endpoint_returns_allowed_data(self):
        expected = [{"id": "8a", "name": "8A"}]
        with patch.object(main, "read_sheet", return_value=expected) as read_source:
            result = main.get_sheet_data("Classes")
        self.assertEqual(result, {"sheet": "Classes", "data": expected})
        read_source.assert_called_once_with("Classes")

    def test_legacy_supplement_endpoint_fails_closed(self):
        with patch.object(main, "read_sheet") as read_source:
            with self.assertRaises(HTTPException) as raised:
                main.get_supplements()
        self.assertEqual(raised.exception.status_code, 403)
        read_source.assert_not_called()

    def test_internal_sync_reader_can_read_private_activity_collection(self):
        expected = [{"student_id": "student-123", "title": "Robotics"}]
        with patch.object(main, "load_configured_sheet", return_value=expected) as read_source:
            result = main.read_sheet("Supplements")
        self.assertEqual(result, expected)
        read_source.assert_called_once_with("Supplements")

    def test_settings_and_devices_are_not_public(self):
        for endpoint in (main.get_settings, main.get_devices):
            with self.subTest(endpoint=endpoint.__name__):
                with self.assertRaises(HTTPException) as raised:
                    endpoint()
                self.assertEqual(raised.exception.status_code, 404)

    def test_health_reports_configured_source_without_secrets(self):
        with patch.dict(os.environ, {"NAVIGATOR_DATA_SOURCE": "json"}):
            with patch.object(main, "load_configured_sheet", return_value=[{"id": "8a"}]):
                result = main.health()
        self.assertEqual(result, {"status": "ok", "source": "json", "sample_rows": 1})
        self.assertNotIn("token", result)


if __name__ == "__main__":
    unittest.main()
