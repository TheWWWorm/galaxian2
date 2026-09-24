"""Synthetic fixtures only. These tests contain no original game content."""
import hashlib
import json
from pathlib import Path
import plistlib
import stat
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from gof2_content import ContentError, install, verify_cache
from gof2_content.bundle import Bundle, safe_name
from gof2_content.formats import language


def fixture(edition='ios'):
    mac = edition == 'mac'
    info = {'CFBundleIdentifier': 'www.fishlabs.net.gof2mac' if mac else 'www.fishlabs.net.gof2hd',
            'CFBundleShortVersionString': 'fixture', 'CFBundleExecutable': 'DoNotRun'}
    resources = {'data/bin/ships.bin': bytes(36 * (61 if mac else 64)),
                 'data/bin/items.bin': b'opaque', 'data/bin/systems.bin': b'opaque',
                 'data/bin/stations.bin': b'opaque',
                 'data/assets/main/3d/meshes/ship.aem': b'V4AEMesh\0\0',
                 'data/assets/main/3d/textures/ship.aei': b'AEimage\0' + struct.pack('<BHHH', 1, 1, 1, 0) + b'\0' * 4,
                 'data/meshes/legacy.aem': b'V5AEMesh\0\0',
                 'data/textures/ui.aei': b'AEimage\0' + struct.pack('<BHHH', 1, 1, 1, 0) + b'\0' * 4,
                 'gb.lang': b'\0\x03row' * (3371 if mac else 3402),
                 'FMOD_GOF2.fev': b'opaque-events', 'FMOD_GOF2_TEST.fsb': b'opaque-audio'}
    prefix = 'Contents/Resources/' if mac else ''
    files = {prefix + n: data for n, data in resources.items()}
    files['Contents/Info.plist' if mac else 'Info.plist'] = plistlib.dumps(info)
    files['Contents/MacOS/DoNotRun' if mac else 'DoNotRun'] = b'\xcf\xfa\xed\xfeDO NOT EXECUTE'
    files[prefix + 'data/assets/main/shaders/original.vert'] = b'original shader code placeholder'
    return files


def archive(path, edition='ios', files=None, app='Renamed.app'):
    prefix = ('Payload/' if edition == 'ios' else 'folder/') + app + '/'
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as z:
        for name, data in (fixture(edition) if files is None else files).items():
            z.writestr(prefix + name, data)
    return path


class ContentTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.cache = self.root / 'cache'

    def test_both_editions_are_independent_and_never_copy_code(self):
        ids = []
        for edition, count in [('ios', 3402), ('mac', 3371)]:
            source = archive(self.root / f'{edition}.zip', edition)
            dest, manifest = install(source, self.cache)
            ids.append(manifest['content_id'])
            self.assertEqual(manifest['languages']['gb']['records'], count)
            self.assertEqual(manifest['counts']['mesh'], 2)
            self.assertEqual(manifest['counts']['texture'], 2)
            self.assertFalse(any('DoNotRun' in n or n.endswith('.vert') for n in manifest['files']))
            self.assertEqual(manifest['support']['campaign'], 'unsupported')
            self.assertEqual(verify_cache(dest), manifest)
        self.assertNotEqual(*ids)

    def test_repackaging_and_app_directory_preserve_identity(self):
        files = fixture('mac')
        app = self.root / 'Anything.app'
        for name, data in files.items():
            path = app / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        first, manifest = install(app, self.cache)
        second, again = install(archive(self.root / 'arbitrary.data', 'mac', app='Other.app'), self.cache)
        self.assertEqual(first, second)
        self.assertEqual(manifest, again)

    def test_content_change_changes_identity(self):
        source = archive(self.root / 'a.zip')
        first, _ = install(source, self.cache)
        files = fixture()
        files['gb.lang'] = b'\0\x03new' + files['gb.lang'][5:]
        second, _ = install(archive(self.root / 'b.zip', files=files), self.cache)
        self.assertNotEqual(first, second)

    def test_newer_mac_layout_is_separate_and_remains_unverified_gameplay(self):
        files = fixture('mac')
        files['Contents/Resources/data/bin/ships.bin'] = bytes(64 * 36)
        files['Contents/Resources/gb.lang'] = b'\0\x03row' * 3385
        dest, manifest = install(archive(self.root / 'newer.zip', 'mac', files=files), self.cache)
        self.assertEqual(manifest['ship_table']['records'], 64)
        self.assertEqual(manifest['languages']['gb']['records'], 3385)
        self.assertEqual(manifest['profile']['edition'], 'mac-full-hd')
        self.assertEqual(manifest['support']['campaign'], 'unsupported')
        self.assertEqual(verify_cache(dest), manifest)
        files['Contents/Resources/gb.lang'] = b'\0\x03row' * 3402
        with self.assertRaisesRegex(ContentError, 'language record count'):
            install(archive(self.root / 'mixed.zip', 'mac', files=files), self.cache)

    def test_cancel_cleans_staging_and_preserves_installed_cache(self):
        source = archive(self.root / 'a.zip')
        dest, expected = install(source, self.cache)
        calls = 0
        def cancel(*_):
            nonlocal calls
            calls += 1
            if calls == 6:
                raise InterruptedError('cancel')
        with self.assertRaises(InterruptedError):
            install(source, self.cache, cancel)
        self.assertEqual(verify_cache(dest), expected)
        self.assertEqual(list(self.cache.iterdir()), [dest])

    def test_layout_metadata_cannot_relabel_a_verified_cache(self):
        dest, manifest = install(archive(self.root / 'mac.zip', 'mac'), self.cache)
        for field, value in [('records', 64), ('records', 61.5), ('record_bytes', 40)]:
            changed = json.loads(json.dumps(manifest))
            changed['ship_table'][field] = value
            (dest / 'manifest.json').write_text(json.dumps(changed))
            with self.assertRaisesRegex(ContentError, 'content layout'):
                verify_cache(dest)
        changed = json.loads(json.dumps(manifest))
        changed['languages']['gb']['records'] = 3385
        (dest / 'manifest.json').write_text(json.dumps(changed))
        with self.assertRaisesRegex(ContentError, 'content layout'):
            verify_cache(dest)
        (dest / 'manifest.json').write_text(json.dumps(manifest))
        self.assertEqual(verify_cache(dest), manifest)

    def test_write_failure_does_not_activate(self):
        source = archive(self.root / 'a.zip')
        with patch('gof2_content.importer.write_definition', side_effect=OSError('disk full')):
            with self.assertRaisesRegex(OSError, 'disk full'):
                install(source, self.cache)
        self.assertEqual(list(self.cache.iterdir()), [])

    def test_existing_corrupt_cache_is_not_replaced(self):
        source = archive(self.root / 'a.zip')
        dest, _ = install(source, self.cache)
        language_path = dest / 'definitions/languages/gb.json'
        language_path.write_text('broken')
        with self.assertRaisesRegex(ContentError, 'size mismatch'):
            install(source, self.cache)
        self.assertEqual(language_path.read_text(), 'broken')
        self.assertEqual(list(self.cache.iterdir()), [dest])

    def test_malformed_and_unknown_layouts_are_rejected(self):
        for name, value, message in [('gb.lang', b'\0\x03ab', 'Truncated'),
                                     ('gb.lang', b'\0\x01\xff', 'UTF-8'),
                                     ('data/bin/ships.bin', b'123', 'ship table'),
                                     ('data/assets/main/3d/meshes/ship.aem', b'unknown', 'AEM'),
                                     ('data/bin/items.bin', b'\x7fELFbinary', 'Executable')]:
            with self.subTest(name=name, message=message):
                files = fixture()
                files[name] = value
                with self.assertRaisesRegex(ContentError, message):
                    install(archive(self.root / 'bad.zip', files=files), self.cache)
                self.assertEqual(list(self.cache.iterdir()), [])

    def test_path_traversal_duplicates_case_collisions_and_links(self):
        for name in ('../outside', '/absolute', 'a\\b', 'C:/a', 'a/./b', 'a//b'):
            with self.subTest(name=name), self.assertRaises(ContentError):
                safe_name(name)
        for bad_name in ('../escape', 'Payload/Renamed.app/gb.lang', 'Payload/Renamed.app/GB.lang'):
            path = archive(self.root / 'bad.zip')
            with zipfile.ZipFile(path, 'a') as z:
                z.writestr(bad_name, b'bad')
            with self.assertRaises(ContentError):
                install(path, self.cache)
        path = archive(self.root / 'link.zip')
        with zipfile.ZipFile(path, 'a') as z:
            link = zipfile.ZipInfo('Payload/Renamed.app/link')
            link.external_attr = (stat.S_IFLNK | 0o777) << 16
            z.writestr(link, '/tmp')
        with self.assertRaisesRegex(ContentError, 'link'):
            install(path, self.cache)

    def test_dmg_missing_ambiguous_and_oversized_diagnostics(self):
        with self.assertRaisesRegex(ContentError, 'readable Mac .dmg'):
            with Bundle(self.root / 'game.dmg'):
                pass
        files = fixture()
        del files['data/bin/stations.bin']
        with self.assertRaisesRegex(ContentError, 'Missing required'):
            install(archive(self.root / 'missing.zip', files=files), self.cache)
        files = fixture()
        files['Nested.app/Info.plist'] = files['Info.plist']
        with self.assertRaisesRegex(ContentError, 'exactly one'):
            install(archive(self.root / 'ambiguous.zip', files=files), self.cache)
        with patch('gof2_content.bundle.MAX_RESOURCE', 8):
            with self.assertRaisesRegex(ContentError, 'limit'):
                install(archive(self.root / 'big.zip'), self.cache)

    def test_cache_path_and_content_integrity(self):
        dest, manifest = install(archive(self.root / 'a.zip'), self.cache)
        path = dest / 'resources/data/bin/items.bin'
        path.write_bytes(b'tamper')
        with self.assertRaisesRegex(ContentError, 'checksum mismatch'):
            verify_cache(dest)
        manifest['files']['definitions/../../outside'] = {'bytes': 1, 'sha256': '0' * 64}
        (dest / 'manifest.json').write_text(json.dumps(manifest))
        # Check traversal independently of earlier damaged resource ordering.
        from gof2_content.importer import checked_path
        with self.assertRaisesRegex(ContentError, 'Unsafe'):
            checked_path(dest, 'definitions/../../outside')

    def test_lock_prevents_concurrent_install(self):
        self.cache.mkdir()
        (self.cache / '.import-lock').mkdir()
        with self.assertRaisesRegex(ContentError, 'holds this cache lock'):
            install(archive(self.root / 'a.zip'), self.cache)
        self.assertTrue((self.cache / '.import-lock').is_dir())

    def test_language_boundary_reader(self):
        self.assertEqual(language(b'\0\0\0\x02ok'), ['', 'ok'])
        for data in (b'', b'\0', b'\0\x02x', b'\0\x01\xff'):
            with self.assertRaises(ContentError):
                language(data)


if __name__ == '__main__':
    unittest.main()
