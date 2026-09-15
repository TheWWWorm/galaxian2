"""Disk-image selection rules; real image extraction is an external-content check."""
from pathlib import Path
import tempfile
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))

from gof2_content.dmg import DmgApp, app_files
from gof2_content.formats import ContentError


def entry(path, size=10, mode='-rw-r--r--', **extra):
    row = {'Path': path, 'Folder': '+' if mode.startswith('d') else '-',
           'Size': str(size), 'Mode': mode, 'Alternate Stream': '-'}
    row.update(extra)
    return '\n'.join(f'{key} = {value}' for key, value in row.items()) + '\n\n'


class DiskImageTests(unittest.TestCase):
    def listing(self):
        return (entry('Volume/Applications', mode='lrwxr-xr-x')
                + entry('Volume/Renamed.app/Contents/Info.plist')
                + entry('Volume/Renamed.app/Contents/MacOS/Game'))

    def test_only_regular_application_files_are_selected(self):
        app, files = app_files(self.listing())
        self.assertEqual(app, 'Volume/Renamed.app')
        self.assertEqual(len(files), 2)
        self.assertNotIn('Volume/Applications', files)

    def test_reject_ambiguous_unsafe_and_linked_app_paths(self):
        for extra in [entry('Volume/Other.app/Contents/Info.plist'),
                      entry('../outside'), entry('Volume/Renamed.app/link', mode='lrwxrwxrwx'),
                      entry('Volume/Renamed.app/Contents/MacOS/game')]:
            with self.subTest(extra=extra), self.assertRaises(ContentError):
                app_files(self.listing() + extra)

    def test_reject_size_limits_encryption_and_listing_injection(self):
        for extra in [entry('Volume/Renamed.app/large', 300 * 1024 * 1024),
                      entry('Volume/Renamed.app/encrypted', Encrypted='+'),
                      'Path = x\nPath = y\n\n', 'unrecognized output\n\n']:
            with self.subTest(extra=extra), self.assertRaises(ContentError):
                app_files(self.listing() + extra)

    def test_missing_or_invalid_disk_image_does_not_extract(self):
        with tempfile.TemporaryDirectory() as directory:
            image = Path(directory) / 'Game.dmg'
            with self.assertRaises(ContentError), DmgApp(image):
                self.fail('Missing image was accepted')
            image.write_bytes(b'x' * 512)
            with self.assertRaisesRegex(ContentError, 'UDIF'), DmgApp(image):
                self.fail('Unrecognized image was accepted')

    def test_cancelled_extraction_removes_staging(self):
        with tempfile.TemporaryDirectory() as directory:
            image = Path(directory) / 'Game.dmg'; image.write_bytes(b'koly' + b'\0' * 508)
            work = Path(directory) / 'work'; work.mkdir()
            with patch.dict('os.environ', {'GOF2_7ZIP': '/test/tool'}), \
                    patch.object(DmgApp, 'run_tool', side_effect=InterruptedError('cancelled')):
                with self.assertRaises(InterruptedError), DmgApp(image, work=work):
                    self.fail('Cancelled extraction was accepted')
            self.assertEqual(list(work.iterdir()), [])
