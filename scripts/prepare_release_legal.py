#!/usr/bin/env python3
"""Collect pinned notices without replacing their licence with a blanket GPL claim."""
from pathlib import Path
import argparse, json, shutil, urllib.request

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--cardinal', type=Path, required=True)
parser.add_argument('--dependencies', type=Path, required=True)
args = parser.parse_args()
destination = root / 'legal'
for base, label in [(args.cardinal, 'Cardinal'), (args.dependencies, 'Dependencies')]:
    for path in base.rglob('*'):
        relative = path.relative_to(base)
        if not path.is_file() or any(part in ('.git', 'build', 'bin', 'node_modules') for part in relative.parts): continue
        if not any(token in path.name.lower() for token in ('license', 'licence', 'copying', 'copyright', 'notice')): continue
        if path.stat().st_size > 2_000_000: continue
        try: path.read_text(encoding='utf-8')
        except (UnicodeError, OSError): continue
        target = destination / 'upstream' / label / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
for name in ('LICENSE.txt', 'COPYRIGHT.txt'):
    target = destination / ('Godot-' + name)
    if not target.exists():
        urllib.request.urlretrieve('https://raw.githubusercontent.com/godotengine/godot/4.5.1-stable/' + name, target)
for name in ('LICENSES.md', 'LICENSE-PERMISSIONS.md'):
    shutil.copy2(args.cardinal / 'docs' / name, destination / name)
entries = [{'label': 'Cardinal 3D — credits & terms', 'path': 'NOTICE.txt'},
           {'label': 'Software — GPL version 3', 'path': 'GPL-3.0.txt'},
           {'label': 'Cardinal — module code & artwork licences', 'path': 'LICENSES.md'},
           {'label': 'Cardinal — artwork permissions', 'path': 'LICENSE-PERMISSIONS.md'},
           {'label': 'Godot — licence', 'path': 'Godot-LICENSE.txt'},
           {'label': 'Godot — third-party notices', 'path': 'Godot-COPYRIGHT.txt'}]
for path in sorted((destination / 'upstream').rglob('*')):
    if path.is_file():
        relative = path.relative_to(destination).as_posix()
        entries.append({'label': relative.removeprefix('upstream/'), 'path': relative})
(destination / 'index.json').write_text(json.dumps(entries, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
shutil.copytree(destination, root / 'godot/legal', dirs_exist_ok=True)
print(f'Collected {len(entries)} legal documents; retained original relative paths and terms.')
