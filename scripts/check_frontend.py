#!/usr/bin/env python3
"""Godot can exit zero after a script error; make frontend checks fail reliably."""
from pathlib import Path
import subprocess
import sys
import os
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='cardinal-frontend-') as isolated:
    env = os.environ.copy()
    env['CARDINAL_EMBEDDED_USER_DIR'] = isolated
    display = ['--rendering-method', 'gl_compatibility', '--resolution', '1440x900'] if '--graphics' in sys.argv[3:] else ['--headless']
    result = subprocess.run([sys.argv[1], *display, '--audio-driver', 'Dummy', '--path', str(root / 'godot'), '--script', sys.argv[2]], env=env, capture_output=True, text=True, timeout=60)
output = result.stdout + result.stderr
print(output, end='')
sys.exit(1 if result.returncode or 'SCRIPT ERROR:' in output or '\nERROR:' in output or ': PASS' not in output else 0)
