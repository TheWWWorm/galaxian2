"""Synthetic Mac app ZIP checks for the on-device import handoff."""
from pathlib import Path
import json
import os
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "platform/android_importer"))
sys.path.insert(0, str(ROOT / "tests"))

import android_import_worker as worker
from gof2_content.dmg import DmgApp
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
        native = self.root / "native"
        native.mkdir()
        self.extractor = native / "libgof2_7zz.so"
        self.extractor.write_bytes(b"bundled extractor test")
        self.extractor.chmod(0o755)

    def dmg(self):
        image = self.work / "source.dmg"
        image.write_bytes(b"koly" + b"\0" * 508)
        return image

    def previous_import(self):
        previous = self.data / "imports/previous/installation.json"
        previous.parent.mkdir(parents=True)
        previous.write_text("unchanged")
        return previous

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
        self.assertEqual(prepare.call_args.args[0].name, "Renamed.app")
        self.assertEqual(prepare.call_args.args[1], self.data / "imports")

    def test_cancel_before_extraction_preserves_previous_import(self):
        previous = self.previous_import()
        self.cancel.write_text("cancel")
        with patch.object(worker, "prepare") as prepare:
            worker.run(self.source, self.data, self.status, self.cancel)
        self.assertEqual(json.loads(self.status.read_text())["state"], "cancelled")
        self.assertEqual(previous.read_text(), "unchanged")
        self.assertFalse((self.root / "extracted").exists())
        prepare.assert_not_called()

    def test_dmg_uses_original_image_for_shared_receipt_and_restores_extractor(self):
        dmg = self.dmg()
        receipt = self.data / "imports/receipt.json"
        calls = []

        def prepare(source, store, checkpoint):
            calls.append((source, store, os.environ.get("GOF2_7ZIP"), source_fingerprint(source)[0]))
            checkpoint("Prepared image", 0.9)
            return receipt, {"format": "mac-dmg"}

        with patch.dict(os.environ, {"GOF2_7ZIP": "previous"}), \
                patch.object(worker, "verify_native_decoders"), patch.object(worker, "prepare", side_effect=prepare):
            worker.run(dmg, self.data, self.status, self.cancel, str(self.extractor))
            self.assertEqual(os.environ["GOF2_7ZIP"], "previous")
        self.assertEqual(calls, [(dmg, self.data / "imports", str(self.extractor), "mac-dmg")])
        self.assertEqual(json.loads(self.status.read_text())["receipt"], str(receipt))
        self.assertEqual(json.loads(self.status.read_text())["state"], "ready")
        self.assertFalse((self.work / "extracted").exists())

    def test_missing_or_invalid_native_extractor_preserves_previous_import(self):
        previous = self.previous_import()
        dmg = self.dmg()
        wrong = self.root / "native/other.so"
        wrong.write_bytes(b"test")
        wrong.chmod(0o755)
        linked = self.root / "linked"
        linked.mkdir()
        link = linked / "libgof2_7zz.so"
        link.symlink_to(self.extractor)
        disabled = self.root / "disabled"
        disabled.mkdir()
        no_execute = disabled / "libgof2_7zz.so"
        no_execute.write_bytes(b"test")
        no_execute.chmod(0o644)
        for candidate in (None, "libgof2_7zz.so", str(wrong), str(link), str(no_execute)):
            with self.subTest(candidate=candidate), patch.object(worker, "prepare") as prepare:
                worker.run(dmg, self.data, self.status, self.cancel, candidate)
                status = json.loads(self.status.read_text())
                self.assertEqual(status["state"], "failed")
                self.assertIn("extractor", status["message"])
                self.assertEqual(previous.read_text(), "unchanged")
                prepare.assert_not_called()

    def test_malformed_dmg_fails_without_changing_previous_import(self):
        previous = self.previous_import()
        dmg = self.work / "source.dmg"
        dmg.write_bytes(b"x" * 512)
        with patch.object(worker, "verify_native_decoders"), \
                patch("gof2_content.game_install.requirements"):
            worker.run(dmg, self.data, self.status, self.cancel, str(self.extractor))
        status = json.loads(self.status.read_text())
        self.assertEqual(status["state"], "failed")
        self.assertIn("UDIF", status["message"])
        self.assertEqual(previous.read_text(), "unchanged")
        self.assertEqual(list((self.data / "imports").iterdir()), [previous.parent])

    def test_dmg_source_over_eight_gib_is_rejected_before_preparation(self):
        previous = self.previous_import()
        dmg = self.dmg()
        with dmg.open("r+b") as stream:
            stream.truncate(worker.MAX_SOURCE + 1)
        with patch.object(worker, "prepare") as prepare:
            worker.run(dmg, self.data, self.status, self.cancel, str(self.extractor))
        status = json.loads(self.status.read_text())
        self.assertEqual(status["state"], "failed")
        self.assertIn("8 GiB", status["message"])
        self.assertEqual(previous.read_text(), "unchanged")
        prepare.assert_not_called()

    def test_cancel_during_dmg_extraction_removes_stage_and_preserves_previous_import(self):
        previous = self.previous_import()
        dmg = self.dmg()
        stages = []
        listing = ("Path = Volume/Renamed.app/Contents/Info.plist\nFolder = -\nSize = 10\n"
                   "Mode = -rw-r--r--\nAlternate Stream = -\n\n"
                   "Path = Volume/Renamed.app/Contents/MacOS/Game\nFolder = -\nSize = 10\n"
                   "Mode = -rw-r--r--\nAlternate Stream = -\n\n")

        def run_tool(app, tool, arguments, report, message):
            stages.append(report.parent)
            if arguments[0] == "l":
                return listing
            self.cancel.write_text("cancel")
            app.checkpoint(message, 0.5)
            self.fail("Extraction continued after cancellation")

        with patch.object(worker, "verify_native_decoders"), \
                patch("gof2_content.game_install.requirements"), \
                patch.object(DmgApp, "run_tool", run_tool), \
                patch.dict(os.environ, {"GOF2_7ZIP": "previous"}):
            worker.run(dmg, self.data, self.status, self.cancel, str(self.extractor))
            self.assertEqual(os.environ["GOF2_7ZIP"], "previous")
        self.assertEqual(json.loads(self.status.read_text())["state"], "cancelled")
        self.assertEqual(previous.read_text(), "unchanged")
        self.assertEqual(len(stages), 2)
        self.assertTrue(all(not stage.exists() for stage in stages))
        self.assertEqual(list((self.data / "imports").iterdir()), [previous.parent])

    def test_low_storage_fails_without_changing_previous_import(self):
        previous = self.previous_import()
        with patch.object(worker, "_available", return_value=worker.HEADROOM - 1), \
                patch.object(worker, "prepare") as prepare:
            worker.run(self.dmg(), self.data, self.status, self.cancel, str(self.extractor))
        status = json.loads(self.status.read_text())
        self.assertEqual(status["state"], "failed")
        self.assertIn("storage", status["message"])
        self.assertEqual(previous.read_text(), "unchanged")
        prepare.assert_not_called()


if __name__ == "__main__":
    unittest.main()
