import argparse
import contextlib
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import run_checks


class CheckRunnerTests(unittest.TestCase):
    def test_script_error_is_failure_even_with_zero_exit(self):
        report, _ = run_checks.execute([sys.executable, '-c', 'print("SCRIPT ERROR: bad state")'], 5, os.environ.copy())
        self.assertFalse(report['passed'])
        self.assertEqual(report['exit_code'], 0)

    def test_timeout_is_failure(self):
        report, _ = run_checks.execute([sys.executable, '-c', 'import time; time.sleep(2)'], .05, os.environ.copy())
        self.assertFalse(report['passed'])
        self.assertEqual(report['exit_code'], 124)

    def test_relative_fixture_paths_are_relative_to_args_file(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'args.json'
            path.write_text(json.dumps(['content', 'bindings']))
            args = argparse.Namespace(args_file=path, content=None, bindings=None, visuals=None)
            self.assertEqual(run_checks.content_arguments(args), [str(Path(folder) / name) for name in ('content', 'bindings')])

    def test_content_inputs_cannot_be_mixed(self):
        args = argparse.Namespace(args_file=Path('args.json'), content=Path('content'), bindings=None, visuals=None)
        with self.assertRaises(ValueError):
            run_checks.content_arguments(args)

    def test_private_outputs_cannot_enter_source(self):
        with self.assertRaises(argparse.ArgumentTypeError):
            run_checks.output_path(run_checks.ROOT / 'report.json')

    def test_test_selection_cannot_escape_test_folder(self):
        args = run_checks.parser().parse_args(['native', '../../tools/run_checks.py', '--godot', 'godot'])
        with self.assertRaises(ValueError):
            run_checks.command(args)


    def test_scenario_capture_preserves_previous_file_on_failure(self):
        self.assert_scenario_promotion(passed=False, writes=True, expected='previous')

    def test_scenario_capture_requires_an_output_even_after_zero_exit(self):
        self.assert_scenario_promotion(passed=True, writes=False, expected='previous')

    def test_passing_scenario_capture_replaces_previous_file(self):
        self.assert_scenario_promotion(passed=True, writes=True, expected='captured')

    def assert_scenario_promotion(self, passed, writes, expected):
        with tempfile.TemporaryDirectory() as folder:
            target = Path(folder) / 'scenario.bin'
            target.write_text('previous')
            def fake_execute(cmd, timeout, env, log):
                if writes:
                    Path(env['GOF2_SCENARIO_OUTPUT']).write_text('captured')
                return {'passed': passed, 'exit_code': 0, 'elapsed_seconds': .01}, ''
            with patch.object(sys, 'argv', ['run_checks.py', 'native', 'asset_readers', '--godot', 'godot', '--capture-scenario', str(target)]), patch.object(run_checks, 'execute', side_effect=fake_execute), contextlib.redirect_stdout(io.StringIO()):
                code = run_checks.main()
            self.assertEqual(code, 0 if passed and writes else 1)
            self.assertEqual(target.read_text(), expected)
            self.assertFalse(list(Path(folder).glob('*.pending')))

if __name__ == '__main__':
    unittest.main()
