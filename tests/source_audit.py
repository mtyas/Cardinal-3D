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
allowed = {'src/CardinalUI.cpp', 'src/override/ModuleWidget.cpp', 'src/Makefile.cardinal.mk', 'plugins/Makefile', 'dpf', 'src/Rack'}
assert changed <= allowed, f'Unexpected upstream changes: {changed-allowed}'
def verify_overlay(relative, replacements):
    checkout = source / relative
    modified = set(subprocess.check_output(['git', '-C', str(checkout), 'diff', 'HEAD', '--name-only'], text=True).splitlines())
    assert modified <= set(replacements), f'Unexpected changes in {relative}: {modified-set(replacements)}'
    for filename, edits in replacements.items():
        original = subprocess.check_output(['git', '-C', str(checkout), 'show', f'HEAD:{filename}'], text=True)
        expected = original
        for old, new in edits:
            expected = expected.replace(old, new)
        actual = (checkout / filename).read_text()
        assert actual in (original, expected), f'Unexpected edit: {relative}/{filename}'

# Match precisely the Windows resource discovery overlay in install_bridge.py.
verify_overlay('dpf', {
    'distrho/src/DistrhoUtils.cpp': [('  #ifndef STATIC_BUILD\n    if (filename.isNotEmpty())', '  #if !defined(STATIC_BUILD) || defined(DISTRHO_OS_WINDOWS)\n    if (filename.isNotEmpty())')],
    'distrho/src/DistrhoPluginJACK.cpp': [
        ('#ifndef STATIC_BUILD\n# include "../DistrhoPluginUtils.hpp"', '#if !defined(STATIC_BUILD) || defined(DISTRHO_OS_WINDOWS)\n# include "../DistrhoPluginUtils.hpp"'),
        ('   #ifndef STATIC_BUILD\n    // find plugin bundle', '   #if !defined(STATIC_BUILD) || defined(DISTRHO_OS_WINDOWS)\n    // find plugin bundle')],
})
rack_changes = set(subprocess.check_output(['git', '-C', str(source / 'src/Rack'), 'diff', 'HEAD', '--name-only'], text=True).splitlines())
assert rack_changes <= {'dep/speexdsp'}, f'Unexpected Rack changes: {rack_changes}'
# Cardinal's pinned deps/Makefile applies this visibility-only configure patch.
verify_overlay('src/Rack/dep/speexdsp', {'configure.ac': [('__attribute__((visibility("default")))', '')]})
for line in git('submodule', 'status', '--recursive').splitlines():
    assert line.startswith(' '), f'Unpinned submodule: {line}'
print('PASS: pinned recursive source; UI/build overlay and exact Windows resource/configure patches; DSP sources unchanged')
