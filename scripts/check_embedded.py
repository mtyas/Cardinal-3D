#!/usr/bin/env python3
"""Run isolated embedded-engine checks without touching the installed launcher."""
import argparse
import os
import shutil
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]

def run(command, env, expected=None):
    process = subprocess.Popen(list(map(str, command)), env=env, cwd=ROOT, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, text=True, encoding='utf-8', errors='replace')
    try:
        stdout, stderr = process.communicate(timeout=30)
    except subprocess.TimeoutExpired as error:
        if os.name == 'nt':
            subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'], capture_output=True)
        else:
            process.kill()
        captured_stdout, captured_stderr = process.communicate(timeout=10)
        def decode(value):
            return value.decode('utf-8', errors='replace') if isinstance(value, bytes) else (value or '')
        stdout = captured_stdout or decode(error.stdout)
        stderr = captured_stderr or decode(error.stderr)
        raise RuntimeError('Embedded test timed out\n' + stdout + stderr) from error
    if process.returncode or 'assertion failure' in stderr or 'SCRIPT ERROR' in stderr or 'ERROR:' in stderr:
        raise RuntimeError(stdout + stderr)
    if expected and expected not in stdout:
        raise RuntimeError('Missing success marker\n' + stdout + stderr)
    for line in stdout.splitlines():
        if 'PASS' in line:
            print(line)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--godot', type=Path, required=True)
    parser.add_argument('--resources', type=Path, required=True)
    parser.add_argument('--graphics', action='store_true')
    parser.add_argument('--build', type=Path, default=ROOT / 'dist/embedded')
    parser.add_argument('--minimum-models', type=int, default=190)
    args = parser.parse_args()
    project = args.build.resolve() / 'godot'
    env = os.environ.copy()
    if args.graphics: env['CARDINAL_EMBEDDED_REQUIRE_GRAPHICS'] = '1'
    env['CARDINAL_EMBEDDED_MINIMUM_MODELS'] = str(args.minimum_models)
    run([sys.executable, ROOT / 'tests/embedded_host.py', '--dll', args.build.resolve() / 'Cardinal3DEngine.dll',
         '--resources', args.resources.resolve(), '--minimum-models', args.minimum_models], env, '"result": "PASS"')
    godot = args.godot.resolve()
    with tempfile.TemporaryDirectory(prefix='cardinal-godot-embedded-', ignore_cleanup_errors=True) as scratch:
        clean_host = Path(scratch) / 'host'
        shutil.copytree(project, clean_host, ignore=shutil.ignore_patterns('.godot'))
        env['CARDINAL_EMBEDDED_RESOURCES'] = str(args.resources.resolve())
        env['CARDINAL_EMBEDDED_TEST_DIR'] = scratch
        base = [godot, '--headless', '--audio-driver', 'Dummy', '--path', clean_host]
        # Godot #111048: cold extension documentation generation races immediate
        # editor teardown. Frame delay allows its deferred callbacks to finish.
        run(base + ['--editor', '--quit-after', '60', '--frame-delay', '100'], env)
        run(base + ['--script', 'res://test_host.gd'], env, 'PASS: Cardinal DSP inside Godot')
        env['CARDINAL_3D_EMBEDDED'] = '1'
        env['CARDINAL_EMBEDDED_USER_DIR'] = str(Path(scratch) / 'rack-settings')
        env.pop('CARDINAL_EMBEDDED_PATCH', None)
        rack = Path(scratch) / 'rack'
        shutil.copytree(args.build.resolve() / 'rack', rack, ignore=shutil.ignore_patterns('.godot'))
        base = [godot, '--headless', '--audio-driver', 'Dummy', '--path', rack]
        run(base + ['--editor', '--quit-after', '60', '--frame-delay', '100'], env)
        run(base + ['--script', 'res://test_rack.gd'], env, 'PASS: embedded 3D starter rack')
        if args.graphics:
            # Exercise restoration of Godot's real WGL context, not only its
            # headless driver. Use a separate silent, temporary desktop window.
            desktop = [godot, '--audio-driver', 'Dummy', '--path', rack,
                       '--rendering-method', 'gl_compatibility', '--resolution', '960x600']
            env['CARDINAL_EMBEDDED_USER_DIR'] = str(Path(scratch) / 'rack-settings-desktop')
            run(desktop + ['--script', 'res://test_rack.gd'], env, 'PASS: embedded 3D starter rack')

if __name__ == '__main__':
    main()
