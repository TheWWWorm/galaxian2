"""Import worker status reporting while the game polls the status file."""
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import import_game


class ImportWorkerTests(unittest.TestCase):
    def test_status_replace_retries_while_destination_is_held_open(self):
        with tempfile.TemporaryDirectory() as directory:
            status = Path(directory) / 'job.json'
            original = import_game.os.replace
            refusals = [3]

            def held_open(source, target):
                if refusals[0]:
                    refusals[0] -= 1
                    raise PermissionError(5, 'Access is denied')
                original(source, target)

            with patch.object(import_game.os, 'replace', held_open), patch.object(import_game.time, 'sleep'):
                import_game.write_status(status, {'state': 'working'})
            self.assertEqual(status.read_text(), '{"state": "working"}\n')
            self.assertFalse(status.with_suffix('.tmp').exists())

    def test_progress_write_failure_does_not_abort_the_import(self):
        written = []

        def status(path, record):
            if record['state'] == 'working':
                raise PermissionError(5, 'Access is denied')
            written.append(record['state'])

        def prepare(dmg, store, checkpoint):
            checkpoint('Unpacking', 0.5)
            return Path('receipt.json'), {}

        with patch.object(import_game, 'write_status', status), patch.object(import_game, 'prepare', prepare), \
                patch.object(sys, 'argv', ['import_game', 'x.dmg', '--store', 's', '--status', 'j.json']):
            self.assertEqual(import_game.main(), 0)
        self.assertEqual(written, ['ready'])


if __name__ == '__main__':
    unittest.main()
