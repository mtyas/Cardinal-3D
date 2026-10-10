#!/usr/bin/env python3
"""Reject changes outside the authorized UI and build overlay, including gitlinks."""
from pathlib import Path
import json
import subprocess

ROOT = Path(__file__).resolve().parents[1]
source = ROOT / 'vendor/Cardinal'
def git(*args):
    return subprocess.check_output(['git', '-C', str(source), *args], text=True)

pin = json.loads((ROOT / 'upstream.lock.json').read_text())
assert git('rev-parse', 'HEAD').strip() == pin['commit']
changed = set(git('diff', 'HEAD', '--name-only').splitlines())
allowed = {'src/CardinalUI.cpp', 'src/override/ModuleWidget.cpp', 'src/Makefile.cardinal.mk', 'plugins/Makefile'}
assert changed <= allowed, f'Unexpected upstream changes: {changed-allowed}'
for line in git('submodule', 'status', '--recursive').splitlines():
    assert line.startswith(' '), f'Unpinned submodule: {line}'
print('PASS: pinned recursive source; tracked changes confined to two UI files and two Makefiles')
