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
from gof2_content.game_install import prepare, read_receipt, source_fingerprint
from gof2_content.formats import ContentError
from test_content import fixture


class InstallationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.dmg = self.root / 'Renamed.dmg'; self.dmg.write_bytes(b'original-synthetic-input')
        self.store = self.root / 'imports'; self.store.mkdir()
        self.previous = self.store / 'previous'; self.previous.mkdir()
        (self.previous / 'keep').write_bytes(b'accepted')

    def mocks(self, stack, app=False, ship_count=61, declarations=None):
        stack.enter_context(patch('gof2_content.game_install.requirements'))
        image = stack.enter_context(patch('gof2_content.game_install.DmgApp'))
        image.return_value.__enter__.return_value = self.root / 'Input.app'
        if not app:
            bundle = stack.enter_context(patch('gof2_content.game_install.Bundle'))
            bundle.return_value.__enter__.return_value = SimpleNamespace(profile={'edition': 'mac-full-hd'})

        def content(_source, output, _checkpoint):
            path = output / ('a' * 64); path.mkdir(parents=True)
            return path, {'content_id': 'a' * 64, 'profile': {'edition': 'mac-full-hd'},
                          'ship_table': {'records': ship_count}}

        def bindings(_source, _base, output, _checkpoint):
            path = output / ('b' * 64); path.mkdir(parents=True)
            (path / 'registrations.json').write_text(json.dumps(declarations or {}))
            return path, {'binding_id': 'b' * 64}, {'missing_resources': []}

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

    def test_newer_layout_checks_prepared_definitions_not_diagnostics(self):
        definitions = {name: {'verified': True} for name in
                       ('opening_loadout', 'frame_clock', 'station_entry', 'first_flight', 'mido_travel')}
        definitions['mido_travel'].update({name: {'verified': True} for name in
                                           ('arrival_briefing', 'ordinary_contracts', 'suttnar_visit')})
        definitions['early_contracts'] = {'ordinary_generation': {'verified': True}}
        with ExitStack() as stack:
            self.mocks(stack, ship_count=64, declarations=definitions)
            path, record = prepare(self.dmg, self.store)
        self.assertEqual(read_receipt(path), record)
        self.unchanged()

    def test_readable_newer_resources_do_not_activate_an_incomplete_campaign(self):
        with ExitStack() as stack:
            self.mocks(stack, ship_count=64, declarations={'opening_loadout': {'verified': True}})
            with self.assertRaisesRegex(ContentError, 'gameplay data is not supported yet'):
                prepare(self.dmg, self.store)
        self.assertEqual(list(self.store.iterdir()), [self.previous])
        self.unchanged()

    def test_local_travel_alone_does_not_activate_newer_player_import(self):
        definitions = {name: {'verified': True} for name in
                       ('opening_loadout', 'frame_clock', 'station_entry', 'first_flight', 'mido_travel')}
        with ExitStack() as stack:
            self.mocks(stack, ship_count=64, declarations=definitions)
            with self.assertRaisesRegex(ContentError, 'gameplay data is not supported yet'):
                prepare(self.dmg, self.store)
        self.assertEqual(list(self.store.iterdir()), [self.previous])
        self.unchanged()

    def test_receipt_rejects_escape_paths(self):
        path = self.root / 'installation.json'
        path.write_text(json.dumps({'schema': 1, 'format': 'mac-dmg', 'base_content_id': 'a' * 64,
                                    'content': '../elsewhere'}))
        with self.assertRaises(ContentError):
            read_receipt(path)

    def app(self):
        app = self.root / 'Renamed.APP'
        for name, data in fixture('mac').items():
            path = app / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(data)
        return app

    def test_app_uses_the_same_transaction_without_extracting_or_copying_executable(self):
        app = self.app(); before = source_fingerprint(app)
        with ExitStack() as stack:
            self.mocks(stack, app=True)
            image = stack.enter_context(patch('gof2_content.game_install.DmgApp'))
            path, record = prepare(app, self.store)
            image.assert_not_called()
        self.assertEqual(record['format'], 'mac-app')
        self.assertEqual(read_receipt(path), record)
        self.assertEqual(record['source_sha256'], before[1])
        self.assertEqual(source_fingerprint(app), before)
        self.assertFalse(any(p.name == 'DoNotRun' for p in path.parent.rglob('*')))
        self.unchanged()

    def test_app_mutation_during_preparation_does_not_activate(self):
        app = self.app()
        def checkpoint(message, _ratio):
            if message == 'Checking your Mac application' and list(self.store.glob('.prepare-*')):
                target = app / 'Contents/Resources/gb.lang'
                target.write_bytes(target.read_bytes().replace(b'row', b'new', 1))
        with ExitStack() as stack:
            self.mocks(stack, app=True)
            with self.assertRaisesRegex(ContentError, 'changed during preparation'):
                prepare(app, self.store, checkpoint)
        self.assertEqual(list(self.store.iterdir()), [self.previous])

    def test_app_cancellation_preserves_previous_installation(self):
        app = self.app()
        def checkpoint(message, _ratio):
            if message == 'Finishing the Mac game import':raise InterruptedError('cancelled')
        with ExitStack() as stack:
            self.mocks(stack, app=True)
            with self.assertRaises(InterruptedError):prepare(app, self.store, checkpoint)
        self.assertEqual(list(self.store.iterdir()), [self.previous])

    def test_app_source_identity_ignores_store_receipts_but_tracks_resource_bytes(self):
        app = self.app(); before = source_fingerprint(app)
        receipt = app / 'Contents/_MASReceipt/receipt'; receipt.parent.mkdir(); receipt.write_bytes(b'private store metadata')
        self.assertEqual(source_fingerprint(app), before)
        path = app / 'Contents/Resources/gb.lang'; path.write_bytes(path.read_bytes().replace(b'row', b'new', 1))
        self.assertNotEqual(source_fingerprint(app)[1], before[1])

    def test_app_store_inside_source_is_rejected_before_creating_files(self):
        app = self.app(); store = app / 'imports'
        with patch('gof2_content.game_install.requirements'), self.assertRaisesRegex(ContentError, 'separate'):
            prepare(app, store)
        self.assertFalse(store.exists())
