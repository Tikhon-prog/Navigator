import json
import unittest
from unittest.mock import patch

from fastapi import HTTPException

from backend import main
from backend.yandex_cloud_function import index


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
