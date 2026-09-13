import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from source_checks import manifest_files, source_closure


class SourceChecksTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.write('game/main.gd', 'extends RefCounted\n')
        self.write('game/main.gd.uid', 'uid://abc123\n')
        self.manifest(['game/main.gd', 'game/main.gd.uid'])

    def write(self, name, text):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def manifest(self, files):
        self.write('source-manifest.json', json.dumps({'files': files}))

    def test_missing_dependency_is_rejected(self):
        self.write('game/main.gd', 'extends "res://missing.gd"\n')
        with self.assertRaisesRegex(ValueError, 'missing from source allowlist'):
            source_closure(self.root)

    def test_shader_and_scene_dependencies_are_checked(self):
        self.write('game/scene.tscn', '[ext_resource path="res://main.gd" type="Script"]\n')
        self.write('game/a.gdshader', '#include "res://missing.gdshaderinc"\n')
        self.manifest(['game/main.gd', 'game/main.gd.uid', 'game/scene.tscn', 'game/a.gdshader'])
        with self.assertRaisesRegex(ValueError, 'missing.gdshaderinc'):
            source_closure(self.root)

    def test_escaping_and_symlinked_entries_are_rejected(self):
        self.manifest(['../outside.py'])
        with self.assertRaises(ValueError):
            manifest_files(self.root)
        (self.root / 'linked.py').symlink_to(self.root / 'game/main.gd')
        self.manifest(['linked.py'])
        with self.assertRaisesRegex(ValueError, 'Symlink'):
            manifest_files(self.root)

    def test_original_binary_and_cache_are_rejected(self):
        for name in ('game/original.bin', 'local/fixture.json'):
            self.write(name, '{}')
            self.manifest([name])
            with self.assertRaises(ValueError):
                manifest_files(self.root)

    def test_duplicate_and_unlisted_uids_are_rejected(self):
        self.write('game/extra.gd.uid', 'uid://abc123\n')
        with self.assertRaisesRegex(ValueError, 'UID missing'):
            source_closure(self.root)
        self.write('game/extra.gd', 'extends RefCounted\n')
        self.manifest(['game/main.gd', 'game/main.gd.uid', 'game/extra.gd', 'game/extra.gd.uid'])
        with self.assertRaisesRegex(ValueError, 'duplicate UID'):
            source_closure(self.root)

    def test_unlisted_shader_uid_is_rejected(self):
        self.write('game/material.gdshader', 'shader_type spatial;\n')
        self.write('game/material.gdshader.uid', 'uid://shader123\n')
        self.manifest(['game/main.gd', 'game/main.gd.uid', 'game/material.gdshader'])
        with self.assertRaisesRegex(ValueError, 'Resource UID missing'):
            source_closure(self.root)

    def test_valid_source_closes(self):
        self.write('game/child.gd', 'extends "res://main.gd"\n')
        self.manifest(['game/main.gd', 'game/main.gd.uid', 'game/child.gd'])
        report = source_closure(self.root)
        self.assertEqual(report['script_inheritance_references'], 1)
        self.assertEqual(report['unique_uids'], 1)


if __name__ == '__main__':
    unittest.main()
