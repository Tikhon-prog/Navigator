import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from fastapi import HTTPException

from backend.data_sources import load_configured_sheet


class DataSourceAdapterTests(unittest.TestCase):
    def test_json_adapter_reads_allowlisted_collection(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "school.json"
            path.write_text(
                json.dumps({"Classes": [{"id": "8A", "name": "8А"}]}, ensure_ascii=False),
                encoding="utf-8",
            )
            with patch.dict(os.environ, {
                "NAVIGATOR_DATA_SOURCE": "json",
                "NAVIGATOR_DATA_JSON_PATH": str(path),
            }):
                self.assertEqual(
                    load_configured_sheet("Classes"),
                    [{"id": "8A", "name": "8А"}],
                )

    def test_json_adapter_returns_empty_list_for_missing_collection(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "school.json"
            path.write_text("{}", encoding="utf-8")
            with patch.dict(os.environ, {
                "NAVIGATOR_DATA_SOURCE": "json",
                "NAVIGATOR_DATA_JSON_PATH": str(path),
            }):
                self.assertEqual(load_configured_sheet("Classes"), [])

    def test_private_collections_are_not_allowed_by_generic_adapter(self):
        with patch.dict(os.environ, {"NAVIGATOR_DATA_SOURCE": "json"}):
            for name in ("Admins", "AuditLog", "Devices", "Settings"):
                with self.subTest(name=name), self.assertRaises(HTTPException) as raised:
                    load_configured_sheet(name)
                self.assertEqual(raised.exception.status_code, 404)

    def test_unconfigured_json_path_fails_closed(self):
        with patch.dict(os.environ, {
            "NAVIGATOR_DATA_SOURCE": "json",
            "NAVIGATOR_DATA_JSON_PATH": "",
        }):
            with self.assertRaises(HTTPException) as raised:
                load_configured_sheet("Classes")
            self.assertEqual(raised.exception.status_code, 503)

    def test_unknown_source_is_rejected(self):
        with patch.dict(os.environ, {"NAVIGATOR_DATA_SOURCE": "unsupported"}):
            with self.assertRaises(HTTPException) as raised:
                load_configured_sheet("Classes")
            self.assertEqual(raised.exception.status_code, 503)

    def test_remote_http_source_requires_https(self):
        with patch.dict(os.environ, {
            "NAVIGATOR_DATA_SOURCE": "http",
            "NAVIGATOR_DATA_API_URL": "http://data.example.org",
        }):
            with self.assertRaises(HTTPException) as raised:
                load_configured_sheet("Classes")
            self.assertEqual(raised.exception.status_code, 503)


if __name__ == "__main__":
    unittest.main()
