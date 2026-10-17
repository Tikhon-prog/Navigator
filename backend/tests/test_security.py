import json
import os
import unittest
from types import SimpleNamespace
from unittest.mock import patch

from fastapi import HTTPException

from backend import main
from backend import school_api
from backend.yandex_cloud_function import index


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
    def test_generic_endpoint_rejects_private_sheets_without_reading_source(self):
        for sheet_name in ("Admins", "AuditLog", "Devices", "Settings"):
            with self.subTest(sheet_name=sheet_name):
                with patch.object(main, "read_sheet") as read_sheet:
                    with self.assertRaises(HTTPException) as raised:
                        main.get_sheet_data(sheet_name)
                    self.assertEqual(raised.exception.status_code, 404)
                    read_sheet.assert_not_called()

    def test_schema_rejects_private_sheets_before_upstream_access(self):
        with patch.object(main, "load_workbook") as load_workbook:
            with self.assertRaises(HTTPException) as raised:
                main.get_schema("Admins")
            self.assertEqual(raised.exception.status_code, 404)
            load_workbook.assert_not_called()

    def test_low_level_reader_rejects_private_sheets_before_upstream_access(self):
        with patch.object(main, "load_workbook") as load_workbook:
            with self.assertRaises(HTTPException) as raised:
                main.read_sheet("Admins")
            self.assertEqual(raised.exception.status_code, 404)
            load_workbook.assert_not_called()

    def test_public_generic_endpoint_still_returns_allowed_data(self):
        expected = [{"id": "8a", "name": "8A"}]
        with patch.object(main, "read_sheet", return_value=expected) as read_sheet:
            result = main.get_sheet_data("Classes")
        self.assertEqual(result, {"sheet": "Classes", "data": expected})
        read_sheet.assert_called_once_with("Classes")

    def test_settings_and_devices_are_not_public(self):
        for endpoint in (main.get_settings, main.get_devices):
            with self.subTest(endpoint=endpoint.__name__):
                with self.assertRaises(HTTPException) as raised:
                    endpoint()
                self.assertEqual(raised.exception.status_code, 404)

    def test_workbook_cache_avoids_repeated_provider_downloads(self):
        main._cached_workbook_bytes = None
        main._cached_workbook_at = 0.0
        responses = [
            SimpleNamespace(status_code=200, json=lambda: {"href": "https://download.example/file"}),
            SimpleNamespace(status_code=200, content=b"workbook-bytes"),
        ]
        try:
            with patch.dict(os.environ, {"YANDEX_OAUTH_TOKEN": "test-token"}):
                with patch.object(main.requests, "get", side_effect=responses) as get:
                    with patch.object(main, "monotonic", side_effect=[100.0, 101.0, 102.0]):
                        first = main.download_master_file()
                        second = main.download_master_file()
            self.assertEqual(first, b"workbook-bytes")
            self.assertEqual(second, b"workbook-bytes")
            self.assertEqual(get.call_count, 2)
        finally:
            main._cached_workbook_bytes = None
            main._cached_workbook_at = 0.0


class CloudFunctionSecurityTests(unittest.TestCase):
    def test_admin_login_fails_closed_until_server_auth_is_implemented(self):
        result = index.handler({"path": "/admin/login", "httpMethod": "POST", "body": "{}"}, None)
        self.assertEqual(result["statusCode"], 503)
        self.assertFalse(json.loads(result["body"])["ok"])

    def test_internal_errors_do_not_leak_exception_details(self):
        with patch.object(index, "read_grid", side_effect=RuntimeError("private-provider-detail")):
            result = index.handler({"path": "/schedule", "httpMethod": "GET"}, None)
        self.assertEqual(result["statusCode"], 500)
        self.assertNotIn("private-provider-detail", result["body"])
        self.assertEqual(json.loads(result["body"])["error"], "internal_error")


if __name__ == "__main__":
    unittest.main()
