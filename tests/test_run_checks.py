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
    def test_focused_discovery_imports_the_reader_package_independently(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'tools').mkdir()
            (root / 'tests').mkdir()
            (root / 'tools/reader_probe.py').write_text('VALUE = 17\n')
            (root / 'tests/test_probe.py').write_text('import unittest\nimport reader_probe\nclass Probe(unittest.TestCase):\n    def test_value(self):\n        self.assertEqual(reader_probe.VALUE, 17)\n')
            with patch.object(run_checks, 'ROOT', root), patch.object(sys, 'argv', ['run_checks.py', 'python', '--pattern', 'test_probe.py']), contextlib.redirect_stdout(io.StringIO()) as output:
                self.assertEqual(run_checks.main(), 0)
            self.assertIn('Ran 1 test', output.getvalue())

    def test_empty_python_selection_is_not_a_passing_check(self):
        with patch.object(sys, 'argv', ['run_checks.py', 'python', '--pattern', 'no_matching_test_91f5.py']), contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(run_checks.main(), 1)
        self.assertIn('No Python tests ran', output.getvalue())

    def test_both_godot_leak_messages_fail_the_check(self):
        for message in ('WARNING: ObjectDB instances leaked at exit',
                        'WARNING: 2 ObjectDB instances were leaked at exit'):
            with self.subTest(message=message):
                report, _ = run_checks.execute([sys.executable, '-c', 'print(' + repr(message) + ')'],
                                              5, os.environ.copy())
                self.assertFalse(report['passed'])

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

    def test_gpu_uses_the_project_renderer_unless_overridden(self):
        args = run_checks.parser().parse_args(['native', 'asset_readers', '--godot', 'godot', '--gpu'])
        cmd = run_checks.command(args)
        self.assertNotIn('--rendering-method', cmd)
        self.assertNotIn('--rendering-driver', cmd)
        self.assertNotIn('--headless', cmd)
        args.rendering_method = 'gl_compatibility'
        args.rendering_driver = 'opengl3'
        cmd = run_checks.command(args)
        self.assertEqual(cmd[cmd.index('--rendering-method') + 1], 'gl_compatibility')
        self.assertEqual(cmd[cmd.index('--rendering-driver') + 1], 'opengl3')

    def test_exported_mainloop_does_not_override_its_project_or_script(self):
        args = run_checks.parser().parse_args(['native', 'asset_readers', '--godot', 'benchmark', '--exported', '--profile'])
        cmd = run_checks.command(args)
        self.assertEqual(cmd[0], 'benchmark')
        self.assertNotIn('--path', cmd)
        self.assertNotIn('--script', cmd)
        self.assertIn('--profiling', cmd)
        self.assertIn('--debug', cmd)


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
