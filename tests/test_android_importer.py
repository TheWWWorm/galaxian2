"""Synthetic Mac app ZIP checks for the on-device import handoff."""
from pathlib import Path
import json
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "platform/android_importer"))
sys.path.insert(0, str(ROOT / "tests"))

import android_import_worker as worker
from gof2_content.game_install import source_fingerprint
from gof2_content import install
from test_content import archive


class AndroidImportTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.source = archive(self.root / "source.zip", "mac")
        self.work = self.root / "work"
        self.work.mkdir()
        self.data = self.root / "data"
        self.data.mkdir()
        self.status = self.root / "status.json"
        self.cancel = self.root / "cancel"

    def test_selected_mac_app_zip_preserves_original_content_identity(self):
        app = worker.extract_app(self.source, self.work, lambda *_: None)
        self.assertEqual(app.name, "Renamed.app")
        self.assertTrue((app / "Contents/Info.plist").is_file())
        self.assertFalse((app / "Contents/Resources/data/assets/main/shaders/original.vert").exists())
        self.assertEqual(source_fingerprint(app)[0], "mac-app")
        _, archive_manifest = install(self.source, self.root / "zip-cache")
        _, app_manifest = install(app, self.root / "app-cache")
        self.assertEqual(archive_manifest["content_id"], app_manifest["content_id"])

    def test_ready_status_uses_shared_receipt_and_cleans_staging(self):
        receipt = self.root / "imports/receipt.json"
        with patch.object(worker, "prepare", return_value=(receipt, {})) as prepare:
            worker.run(self.source, self.data, self.status, self.cancel)
        self.assertEqual(json.loads(self.status.read_text())["receipt"], str(receipt))
        self.assertEqual(json.loads(self.status.read_text())["state"], "ready")
        self.assertFalse((self.root / "extracted").exists())
        self.assertEqual(prepare.call_args.args[1], self.data / "imports")

    def test_cancel_before_extraction_preserves_previous_import(self):
        previous = self.data / "imports/previous/installation.json"
        previous.parent.mkdir(parents=True)
        previous.write_text("unchanged")
        self.cancel.write_text("cancel")
        with patch.object(worker, "prepare") as prepare:
            worker.run(self.source, self.data, self.status, self.cancel)
        self.assertEqual(json.loads(self.status.read_text())["state"], "cancelled")
        self.assertEqual(previous.read_text(), "unchanged")
        self.assertFalse((self.root / "extracted").exists())
        prepare.assert_not_called()

    def test_dmg_is_rejected_without_changing_previous_import(self):
        previous = self.data / "imports/previous/installation.json"
        previous.parent.mkdir(parents=True)
        previous.write_text("unchanged")
        dmg = self.work / "original.dmg"
        dmg.write_bytes(b"not a ZIP")
        with patch.object(worker, "prepare") as prepare:
            worker.run(dmg, self.data, self.status, self.cancel)
        status = json.loads(self.status.read_text())
        self.assertEqual(status["state"], "failed")
        self.assertIn("ZIP", status["message"])
        self.assertEqual(previous.read_text(), "unchanged")
        prepare.assert_not_called()


if __name__ == "__main__":
    unittest.main()
