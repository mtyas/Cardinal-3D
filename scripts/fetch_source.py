#!/usr/bin/env python3
"""Fetch only the pinned Cardinal source; suitable for Linux cloud builders."""
from pathlib import Path
import json
import subprocess
import hashlib

ROOT = Path(__file__).resolve().parents[1]

def main():
    pin = json.loads((ROOT / 'upstream.lock.json').read_text())
    source = ROOT / 'vendor/Cardinal'
    source.parent.mkdir(exist_ok=True)
    archive_manifest = source / '.source-snapshot.json'
    if archive_manifest.is_file() and not (source / '.git').exists():
        manifest = json.loads(archive_manifest.read_text())
        if manifest['commit'] != pin['commit']: raise RuntimeError('Source archive pin mismatch')
        for filename, digest in manifest['sha256'].items():
            path = source / filename
            if not path.resolve().is_relative_to(source.resolve()): raise RuntimeError('Unsafe source path')
            if hashlib.sha256(path.read_bytes()).hexdigest() != digest: raise RuntimeError('Source archive changed: ' + filename)
        print('Verified complete pinned Cardinal source archive.')
        return
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
