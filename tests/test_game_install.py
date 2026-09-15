"""Installation transaction tests with synthetic data and injected preparers."""
from contextlib import ExitStack
import hashlib
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from gof2_content.game_install import prepare, read_receipt
from gof2_content.formats import ContentError


class InstallationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.dmg = self.root / 'Renamed.dmg'; self.dmg.write_bytes(b'original-synthetic-input')
        self.store = self.root / 'imports'; self.store.mkdir()
        self.previous = self.store / 'previous'; self.previous.mkdir()
        (self.previous / 'keep').write_bytes(b'accepted')

    def mocks(self, stack):
        stack.enter_context(patch('gof2_content.game_install.requirements'))
        image = stack.enter_context(patch('gof2_content.game_install.DmgApp'))
        image.return_value.__enter__.return_value = self.root / 'Input.app'
        bundle = stack.enter_context(patch('gof2_content.game_install.Bundle'))
        bundle.return_value.__enter__.return_value = SimpleNamespace(profile={'edition': 'mac-full-hd'})

        def content(_source, output, _checkpoint):
            path = output / ('a' * 64); path.mkdir(parents=True)
            return path, {'content_id': 'a' * 64}

        def bindings(_source, _base, output, _checkpoint):
            path = output / ('b' * 64); path.mkdir(parents=True)
            return path, {'binding_id': 'b' * 64}, {}

        def visuals(_base, output, **_kwargs):
            path = output / ('c' * 64); path.mkdir(parents=True)
            return path, {'pack_id': 'c' * 64}

        stack.enter_context(patch('gof2_content.game_install.install', side_effect=content))
        prepare_bindings = stack.enter_context(patch('gof2_content.bindings.prepare', side_effect=bindings))
        stack.enter_context(patch('gof2_content.visuals.prepare', side_effect=visuals))
        return prepare_bindings

    def unchanged(self):
        self.assertEqual((self.previous / 'keep').read_bytes(), b'accepted')
        self.assertEqual(self.dmg.read_bytes(), b'original-synthetic-input')
        self.assertEqual(list(self.store.glob('.prepare-*')), [])

    def test_receipt_activates_only_after_all_preparers_succeed(self):
        with ExitStack() as stack:
            self.mocks(stack)
            path, record = prepare(self.dmg, self.store)
        self.assertEqual(read_receipt(path), record)
        self.assertEqual(record['format'], 'mac-dmg')
        self.assertEqual(record['source_sha256'], hashlib.sha256(self.dmg.read_bytes()).hexdigest())
        self.assertFalse(any(p.suffix == '.app' for p in path.parent.rglob('*')))
        self.unchanged()

    def test_cancel_before_activation_leaves_previous_import(self):
        def checkpoint(message, _ratio):
            if message == 'Finishing the Mac game import':
                raise InterruptedError('cancelled')
        with ExitStack() as stack:
            self.mocks(stack)
            with self.assertRaises(InterruptedError):
                prepare(self.dmg, self.store, checkpoint)
        self.assertEqual(list(self.store.iterdir()), [self.previous])
        self.unchanged()

    def test_failed_binding_preparation_removes_partial_content(self):
        with ExitStack() as stack:
            bindings = self.mocks(stack); bindings.side_effect = ContentError('unsupported source')
            with self.assertRaisesRegex(ContentError, 'unsupported source'):
                prepare(self.dmg, self.store)
        self.assertEqual(list(self.store.iterdir()), [self.previous])
        self.unchanged()

    def test_receipt_rejects_escape_paths(self):
        path = self.root / 'installation.json'
        path.write_text(json.dumps({'schema': 1, 'format': 'mac-dmg', 'base_content_id': 'a' * 64,
                                    'content': '../elsewhere'}))
        with self.assertRaises(ContentError):
            read_receipt(path)
