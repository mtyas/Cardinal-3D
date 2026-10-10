#!/usr/bin/env python3
"""Only reuse a successful private artifact when its native sources match HEAD."""
import json
import os
import subprocess

run_id = str(int(os.environ['SOURCE_RUN']))
result = json.loads(subprocess.check_output(['gh', 'api', f'repos/{os.environ["GH_REPO"]}/actions/runs/{run_id}'], text=True))
if result['conclusion'] != 'success' or result['path'] != '.github/workflows/windows-build.yml':
    raise RuntimeError('Choose a successful Windows desktop build run')
subprocess.run(['git', 'diff', '--exit-code', result['head_sha'], 'HEAD', '--', 'bridge', 'upstream.lock.json', 'scripts/install_bridge.py', 'scripts/build_windows.sh'], check=True)
print('Verified identical pinned native sources; repackaging frontend only.')
