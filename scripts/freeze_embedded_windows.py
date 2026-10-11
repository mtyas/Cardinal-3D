#!/usr/bin/env python3
"""Copy a checked build to a new launch directory, then publish its pointer."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import uuid
from check_embedded import run

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--build', type=Path, default=ROOT / 'dist/embedded-full')
    args = parser.parse_args()
    source = args.build.resolve()
    version = json.loads((ROOT / 'upstream.lock.json').read_text(encoding='utf-8'))['godot']
    godot = ROOT / '.tools/Godot' / f'Godot_v{version}_win64_console.exe'
    if not godot.is_file(): raise RuntimeError(f'Missing pinned Godot: {godot}')
    for name in ('Cardinal/resources/PluginManifests/Cardinal.json', 'rack/project.godot',
                 'rack/bin/Cardinal3DEngine.dll', 'rack/bin/Cardinal3DExtension.dll'):
        if not (source / name).is_file(): raise RuntimeError(f'Missing build file: {name}')
    stamp = datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S')
    target = ROOT.parent / 'runtime' / f'standalone-{stamp}-{uuid.uuid4().hex[:8]}'
    target.mkdir(parents=True)  # A fresh path: never replace a running DLL.
    for folder in ('Cardinal', 'rack'):
        shutil.copytree(source / folder, target / folder, ignore=shutil.ignore_patterns('.godot', '__pycache__'))
    # Populate this copy's class/import cache before its first normal launch.
    # Never copy caches whose absolute paths still point at a development build.
    run([godot, '--headless', '--audio-driver', 'Dummy', '--path', target / 'rack',
         '--editor', '--quit-after', '60', '--frame-delay', '100'], os.environ.copy())
    files = ('rack/bin/Cardinal3DEngine.dll', 'rack/bin/Cardinal3DExtension.dll')
    hashes = {name: hashlib.sha256((target / name).read_bytes()).hexdigest() for name in files}
    revision = subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=ROOT, capture_output=True, text=True)
    status = subprocess.run(['git', 'status', '--porcelain', '--untracked-files=no'], cwd=ROOT, capture_output=True, text=True)
    metadata = dict(runtime=str(target.resolve()), created_utc=stamp, dll_sha256=hashes,
                    source_commit=revision.stdout.strip() if revision.returncode == 0 else None,
                    source_has_changes=bool(status.stdout.strip()) if status.returncode == 0 else None)
    (target / 'snapshot.json').write_text(json.dumps(metadata, indent=2) + '\n', encoding='utf-8')
    pointer = ROOT.parent / 'standalone-runtime.json'
    pending = pointer.with_suffix('.next.json')
    pending.write_text(json.dumps(metadata, indent=2) + '\n', encoding='utf-8')
    os.replace(pending, pointer)
    print(f'Standalone launch copy ready: {target}')

if __name__ == '__main__': main()
