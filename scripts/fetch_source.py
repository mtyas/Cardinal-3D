#!/usr/bin/env python3
"""Fetch only the pinned Cardinal source; suitable for Linux cloud builders."""
from pathlib import Path
import json
import subprocess

ROOT = Path(__file__).resolve().parents[1]

def main():
    pin = json.loads((ROOT / 'upstream.lock.json').read_text())
    source = ROOT / 'vendor/Cardinal'
    source.parent.mkdir(exist_ok=True)
    fresh = not source.exists()
    if fresh:
        subprocess.run(['git', 'clone', '--no-checkout', pin['repository'], str(source)], check=True)
    actual = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
    if fresh or actual != pin['commit']:
        dirty = subprocess.check_output(['git', '-C', str(source), 'status', '--porcelain'], text=True)
        if dirty and (source / 'src/CardinalUI.cpp').exists():
            raise RuntimeError('Preserve local changes before changing the Cardinal pin')
        subprocess.run(['git', '-C', str(source), 'checkout', '--detach', pin['commit']], check=True)
    subprocess.run(['git', '-C', str(source), 'submodule', 'update', '--init', '--recursive', '--jobs', '8'], check=True)

if __name__ == '__main__':
    main()
