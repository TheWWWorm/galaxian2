#!/usr/bin/env python3
"""Run source, Python, editor or native checks with explicit local content paths."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time

from source_checks import source_closure

ROOT = Path(__file__).resolve().parents[1]
ERRORS = re.compile(r'SCRIPT ERROR:|^ERROR:|^FAIL(?:\s|:)|ObjectDB instances (?:were )?leaked|resources still in use at exit', re.MULTILINE)


def output_path(value):
    path = Path(value).expanduser().resolve()
    if path.is_relative_to(ROOT):
        raise argparse.ArgumentTypeError('Keep logs, reports, captures and scenario data outside the source repository')
    return path


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest='kind', required=True)
    for kind in ('source', 'python', 'editor', 'native'):
        s = sub.add_parser(kind)
        s.add_argument('--report', type=output_path)
        if kind == 'source':
            continue
        s.add_argument('--log', type=output_path)
        s.add_argument('--timeout', type=float, default=180)
        if kind == 'python':
            s.add_argument('--pattern', default='test_*.py')
            continue
        s.add_argument('--godot', default=os.environ.get('GOF2_GODOT'))
        if kind == 'editor':
            continue
        s.add_argument('test', help='Script name relative to game/tests, with or without .gd')
        s.add_argument('--args-file', type=Path, help='JSON list of explicit positional content arguments')
        s.add_argument('--content', type=Path)
        s.add_argument('--bindings', type=Path)
        s.add_argument('--visuals', type=Path)
        s.add_argument('--gpu', action='store_true')
        s.add_argument('--rendering-method', choices=['gl_compatibility', 'mobile', 'forward_plus'])
        s.add_argument('--rendering-driver', choices=['opengl3', 'vulkan', 'metal', 'd3d12'])
        s.add_argument('--profile', action='store_true', help='Include Godot script profiler data in the log')
        s.add_argument('--exported', action='store_true', help='Run a test exported as the executable main loop')
        s.add_argument('--captures', type=output_path)
        s.add_argument('--scenario', type=output_path)
        s.add_argument('--capture-scenario', type=output_path)
    return p


def content_arguments(args):
    if args.args_file:
        if args.content or args.bindings or args.visuals:
            raise ValueError('Use --args-file or named content paths, not both')
        values = json.loads(args.args_file.read_text())
        if not isinstance(values, list) or any(not isinstance(v, str) or not v for v in values):
            raise ValueError('The arguments file must contain a list of nonempty path strings')
        # Relative entries belong to the arguments file, not the shell directory.
        return [str((args.args_file.resolve().parent / v).resolve()) for v in values]
    if (args.bindings and not args.content) or (args.visuals and not args.bindings):
        raise ValueError('Bindings require content; visuals require content and bindings')
    return [str(p.expanduser().resolve()) for p in (args.content, args.bindings, args.visuals) if p]


def command(args):
    if args.kind == 'python':
        return [sys.executable, '-m', 'unittest', 'discover', '-s', str(ROOT / 'tests'), '-p', args.pattern, '-v']
    godot = args.godot or shutil.which('godot') or shutil.which('godot4')
    if not godot:
        raise ValueError('Godot was not found; use --godot or GOF2_GODOT')
    cmd = [str(godot), '--path', str(ROOT / 'game')]
    if args.kind == 'editor':
        return cmd + ['--headless', '--editor', '--quit']
    test = args.test.removesuffix('.gd')
    if args.exported:
        cmd = [str(godot)]
    script = (ROOT / 'game/tests' / (test + '.gd')).resolve()
    if not script.is_relative_to(ROOT / 'game/tests') or not script.is_file():
        raise ValueError('Choose an existing script inside game/tests')
    if not args.gpu:
        cmd += ['--headless']
    if args.rendering_method:
        cmd += ['--rendering-method', args.rendering_method]
    if args.rendering_driver:
        cmd += ['--rendering-driver', args.rendering_driver]
    if args.profile:
        cmd += ['--debug', '--profiling']
    if not args.exported:
        cmd += ['--script', 'res://tests/' + script.relative_to(ROOT / 'game/tests').as_posix()]
    cmd += ['--']
    cmd += content_arguments(args)
    if args.captures:
        args.captures.mkdir(parents=True, exist_ok=True)
        cmd.append(str(args.captures))
    return cmd


def execute(cmd, timeout, env, log=None):
    start = time.monotonic()
    if log:
        log.parent.mkdir(parents=True, exist_ok=True)
    with (log.open('w+', encoding='utf-8') if log else tempfile.TemporaryFile(mode='w+', encoding='utf-8')) as stream:
        try:
            result = subprocess.run(cmd, cwd=ROOT, env=env, stdout=stream,
                                    stderr=subprocess.STDOUT, text=True, timeout=timeout)
            code = result.returncode
        except subprocess.TimeoutExpired:
            stream.write('\nCheck exceeded its timeout.\n')
            code = 124
        stream.flush()
        stream.seek(0)
        output = stream.read()
    return {'command': cmd, 'elapsed_seconds': round(time.monotonic() - start, 3),
            'exit_code': code, 'passed': code == 0 and not ERRORS.search(output)}, output


def main():
    p = parser()
    args = p.parse_args()
    pending = None
    try:
        if args.kind == 'source':
            start = time.monotonic()
            report = {'kind': 'source', 'passed': True, 'closure': source_closure(ROOT),
                      'elapsed_seconds': round(time.monotonic() - start, 3)}
            output = json.dumps(report['closure']) + '\n'
        else:
            if args.timeout <= 0:
                raise ValueError('Timeout must be positive')
            env = os.environ.copy()
            env.pop('GOF2_SCENARIO_INPUT', None)
            env.pop('GOF2_SCENARIO_OUTPUT', None)
            if args.kind == 'python':
                # Focused discovery must not depend on another test module
                # having inserted the reader package into sys.path first.
                env['PYTHONPATH'] = os.pathsep.join(filter(None, (str(ROOT / 'tools'), env.get('PYTHONPATH'))))
            if args.kind == 'native':
                if args.scenario and args.capture_scenario:
                    raise ValueError('Choose scenario capture or replay, not both')
                if args.scenario:
                    if not args.scenario.is_file():
                        raise ValueError('Scenario file does not exist; capture it through the integration test first')
                    env['GOF2_SCENARIO_INPUT'] = str(args.scenario)
                if args.capture_scenario:
                    args.capture_scenario.parent.mkdir(parents=True, exist_ok=True)
                    handle, pending_name = tempfile.mkstemp(prefix='.scenario-', suffix='.pending', dir=args.capture_scenario.parent)
                    os.close(handle)
                    pending = Path(pending_name)
                    pending.unlink()
                    env['GOF2_SCENARIO_OUTPUT'] = str(pending)
            report, output = execute(command(args), args.timeout, env, args.log)
            report['kind'] = args.kind
            if args.kind == 'python':
                count = re.search(r'^Ran (\d+) tests? in ', output, re.MULTILINE)
                report['test_count'] = int(count[1]) if count else 0
                if not report['test_count']:
                    report['passed'] = False
                    output += '\nNo Python tests ran; check the selected pattern.\n'
            if pending:
                if report['passed'] and pending.is_file() and pending.stat().st_size:
                    pending.replace(args.capture_scenario)
                    report['scenario'] = str(args.capture_scenario)
                else:
                    report['passed'] = False
                    output += '\nScenario capture did not complete a passing integration run.\n'
        print(output[-6000:], end='')
        print(f"{args.kind}: {'PASS' if report['passed'] else 'FAIL'} in {report['elapsed_seconds']:.3f}s")
        if args.report:
            args.report.parent.mkdir(parents=True, exist_ok=True)
            args.report.write_text(json.dumps(report, indent=2) + '\n')
        return 0 if report['passed'] else 1
    except (OSError, ValueError, KeyError, TypeError) as exc:
        p.error(str(exc))
    finally:
        if pending and pending.exists():
            pending.unlink()


if __name__ == '__main__':
    raise SystemExit(main())
