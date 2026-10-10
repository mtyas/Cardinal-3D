#!/usr/bin/env python3
"""Godot can exit zero after a script error; make frontend checks fail reliably."""
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
result = subprocess.run([sys.argv[1], '--headless', '--path', str(root / 'godot'), '--script', sys.argv[2]], capture_output=True, text=True, timeout=60)
output = result.stdout + result.stderr
print(output, end='')
sys.exit(1 if result.returncode or 'SCRIPT ERROR:' in output or '\nERROR:' in output or ': PASS' not in output else 0)
