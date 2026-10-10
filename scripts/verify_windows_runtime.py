#!/usr/bin/env python3
"""Only reuse a successful private artifact when its native sources match HEAD."""
import json
import os
import subprocess

run_id = str(int(os.environ['SOURCE_RUN']))
result = json.loads(subprocess.check_output(['gh', 'api', f'repos/{os.environ["GH_REPO"]}/actions/runs/{run_id}'], text=True))
if result['conclusion'] != 'success' or result['path'] != '.github/workflows/windows-build.yml':
    raise RuntimeError('Choose a successful Windows desktop build run')
paths = ['bridge', 'upstream.lock.json', 'scripts/install_bridge.py', 'scripts/build_windows.sh']
def native_blobs(revision):
    # Executable-mode changes on shell scripts do not change the compiled runtime.
    return subprocess.check_output(['git', 'ls-tree', '-r', '--format=%(objectname) %(path)', revision, '--', *paths])
if native_blobs(result['head_sha']) != native_blobs('HEAD'):
    raise RuntimeError('Native sources differ; run a full Windows build instead')
print('Verified identical pinned native sources; repackaging frontend only.')
