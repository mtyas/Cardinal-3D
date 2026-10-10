#!/usr/bin/env python3
"""Run the actual Godot rack and native audio for a minute of repeated gestures."""
from pathlib import Path
import json
import os
import secrets
import socket
import subprocess

ROOT = Path(__file__).resolve().parents[1]
build = Path((ROOT / 'build/cardinal-path.txt').read_text().strip())
with socket.socket() as reservation:
    reservation.bind(('127.0.0.1', 0)); port = reservation.getsockname()[1]
env = os.environ.copy()
blank = ROOT / 'build/benchmark-blank.vcv'
blank.write_text(json.dumps(dict(version='2.4.1', modules=[], cables=[])))
env.update(CARDINAL_3D_PORT=str(port), CARDINAL_3D_TOKEN=secrets.token_hex(24), CARDINAL_3D_BLANK_PATCH=str(blank), CARDINAL_3D_BENCHMARK_REPORT=str(ROOT / 'build/frontend-benchmark.json'))
native = subprocess.Popen([str(build / 'bin/CardinalNative.app/Contents/MacOS/CardinalNative')], env=env)
try:
    subprocess.run([str(ROOT / '.tools/Godot.app/Contents/MacOS/Godot'), '--path', str(ROOT / 'godot'), '--script', 'res://tests/benchmark.gd'], env=env, check=True, timeout=120)
    print((ROOT / 'build/frontend-benchmark.json').read_text())
finally:
    native.terminate(); native.wait(timeout=10)
