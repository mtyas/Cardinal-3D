#!/usr/bin/env python3
"""Run isolated embedded-engine checks without touching the installed launcher."""
import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]

def run(command, env, expected=None):
    try:
        result = subprocess.run(list(map(str, command)), env=env, cwd=ROOT, capture_output=True,
                                text=True, encoding='utf-8', errors='replace', timeout=30)
    except subprocess.TimeoutExpired as error:
        def decode(value):
            return value.decode('utf-8', errors='replace') if isinstance(value, bytes) else (value or '')
        stdout, stderr = decode(error.stdout), decode(error.stderr)
        raise RuntimeError('Embedded test timed out\n' + stdout + stderr) from error
    if result.returncode or 'assertion failure' in result.stderr or 'SCRIPT ERROR' in result.stderr or 'ERROR:' in result.stderr:
        raise RuntimeError(result.stdout + result.stderr)
    if expected and expected not in result.stdout:
        raise RuntimeError('Missing success marker\n' + result.stdout + result.stderr)
    for line in result.stdout.splitlines():
        if 'PASS' in line:
            print(line)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--godot', type=Path, required=True)
    parser.add_argument('--resources', type=Path, required=True)
    args = parser.parse_args()
    project = ROOT / 'dist/embedded/godot'
    env = os.environ.copy()
    run([sys.executable, ROOT / 'tests/embedded_host.py', '--dll', ROOT / 'dist/embedded/Cardinal3DEngine.dll',
         '--resources', args.resources.resolve()], env, '"result": "PASS"')
    godot = args.godot.resolve()
    with tempfile.TemporaryDirectory(prefix='cardinal-godot-embedded-') as scratch:
        env['CARDINAL_EMBEDDED_RESOURCES'] = str(args.resources.resolve())
        env['CARDINAL_EMBEDDED_TEST_DIR'] = scratch
        base = [godot, '--headless', '--audio-driver', 'Dummy', '--path', project]
        run(base + ['--editor', '--import', '--quit'], env)
        run(base + ['--script', 'res://test_host.gd'], env, 'PASS: Cardinal DSP inside Godot')

if __name__ == '__main__':
    main()
