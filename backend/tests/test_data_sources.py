import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from fastapi import HTTPException

from backend.data_sources import load_configured_sheet


class DataSourceAdapterTests(unittest.TestCase):
    def test_json_adapter_reads_allowlisted_sheet(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "school.json"
            path.write_text(json.dumps({"Classes": [{"id": "8A", "name": "8А"}]}, ensure_ascii=False), encoding="utf-8")
            with patch.dict(os.environ, {"NAVIGATOR_DATA_SOURCE": "json", "NAVIGATOR_DATA_JSON_PATH": str(path)}):
                self.assertEqual(load_configured_sheet("Classes"), [{"id": "8A", "name": "8А"}])

    def test_json_adapter_rejects_private_sheets(self):
        with patch.dict(os.environ, {"NAVIGATOR_DATA_SOURCE": "json", "NAVIGATOR_DATA_JSON_PATH": "/not-used.json"}):
            with self.assertRaises(HTTPException) as raised:
                load_configured_sheet("Admins")
            self.assertEqual(raised.exception.status_code, 404)

    def test_yandex_mode_defers_to_legacy_reader(self):
        with patch.dict(os.environ, {"NAVIGATOR_DATA_SOURCE": "yandex"}):
            self.assertIsNone(load_configured_sheet("Classes"))


if __name__ == "__main__":
    unittest.main()
