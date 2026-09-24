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

    def test_unlisted_source_dependency_is_rejected(self):
        self.write('game/extra.gd', 'extends RefCounted\n')
        self.write('game/main.gd', 'extends "res://extra.gd"\n')
        with self.assertRaisesRegex(ValueError, 'resource missing from source allowlist: extra.gd'):
            source_closure(self.root)

    def test_project_autoload_dependency_is_rejected(self):
        self.write('game/project.godot', '[autoload]\nPrivate="*res://addons/private/runtime.gd"\n')
        self.write('game/addons/private/runtime.gd', 'extends Node\n')
        self.manifest(['game/main.gd', 'game/main.gd.uid', 'game/project.godot'])
        with self.assertRaisesRegex(ValueError, 'resource missing from source allowlist: addons/private/runtime.gd'):
            source_closure(self.root)

    def test_shader_and_scene_dependencies_are_checked(self):
        self.write('game/scene.tscn', '[ext_resource path="res://main.gd" type="Script"]\n')
        self.write('game/a.gdshader', '#include "res://missing.gdshaderinc"\n')
        self.write('game/a.gdshader.uid', 'uid://shader123\n')
        self.manifest(['game/main.gd', 'game/main.gd.uid', 'game/scene.tscn',
                       'game/a.gdshader', 'game/a.gdshader.uid'])
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
        for name in ('game/original.bin', 'local/fixture.json', 'platform/android_importer/Plugin.class'):
            self.write(name, '{}')
            self.manifest([name])
            with self.assertRaises(ValueError):
                manifest_files(self.root)

    def test_android_plugin_source_requires_explicit_allowlist(self):
        name = 'platform/android_importer/Plugin.java'
        self.write(name, 'final class Plugin {}\n')
        self.assertNotIn(name, manifest_files(self.root))
        self.manifest([name])
        self.assertEqual(manifest_files(self.root), [name])

    def test_allowlisted_script_requires_allowlisted_uid(self):
        self.write('game/extra.gd', 'extends RefCounted\n')
        self.manifest(['game/main.gd', 'game/main.gd.uid', 'game/extra.gd'])
        with self.assertRaisesRegex(ValueError, 'UID missing from source allowlist: game/extra.gd.uid'):
            source_closure(self.root)
        self.write('game/extra.gd.uid', 'uid://extra123\n')
        with self.assertRaisesRegex(ValueError, 'UID missing from source allowlist: game/extra.gd.uid'):
            source_closure(self.root)

    def test_private_orphan_uid_does_not_enter_source_closure(self):
        self.write('game/addons/private/runtime.gd.uid', 'uid://abc123\n')
        report = source_closure(self.root)
        self.assertEqual(report['unique_uids'], 1)

    def test_allowlisted_orphan_uid_is_rejected(self):
        self.write('game/addons/private/runtime.gd.uid', 'uid://private123\n')
        self.manifest(['game/main.gd', 'game/main.gd.uid',
                       'game/addons/private/runtime.gd.uid'])
        with self.assertRaisesRegex(ValueError, 'orphaned'):
            source_closure(self.root)

    def test_duplicate_uids_are_rejected(self):
        self.write('game/extra.gd', 'extends RefCounted\n')
        self.write('game/extra.gd.uid', 'uid://abc123\n')
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
        self.write('game/child.gd.uid', 'uid://child123\n')
        self.manifest(['game/main.gd', 'game/main.gd.uid', 'game/child.gd', 'game/child.gd.uid'])
        report = source_closure(self.root)
        self.assertEqual(report['script_inheritance_references'], 1)
        self.assertEqual(report['unique_uids'], 2)


if __name__ == '__main__':
    unittest.main()
