"""Audit named knob SVG assets across the complete source library, read-only.

This is asset coverage, not proof that every model instantiates these controls.
Runtime descriptors remain the authority for mapping colours to module controls.
"""
import argparse
import collections
import json
from pathlib import Path
import re
import subprocess

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, default=Path('vendor/Cardinal'))
    parser.add_argument('--probe', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=Path('reports/knob-palettes.json'))
    args = parser.parse_args()
    files = sorted(p.resolve() for p in args.source.rglob('*.svg')
                   if re.search(r'knob|davies|daka', p.stem, re.I))
    result = subprocess.run([str(args.probe.resolve())], input=''.join(str(p)+'\n' for p in files),
                            capture_output=True, text=True, check=True)
    assets = []
    for line in result.stdout.splitlines():
        name, color = line.rsplit('\t', 1)
        assets.append({'asset': str(Path(name).relative_to(args.source.resolve())),
                       'body_color': color or None, 'status': 'palette' if color else 'artwork fallback'})
    summary = {'named_knob_assets': len(assets), 'palette_assets': sum(bool(a['body_color']) for a in assets),
               'colours': dict(collections.Counter(a['body_color'] for a in assets if a['body_color']))}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps({'summary': summary, 'assets': assets}, indent=2))
    print(json.dumps(summary, sort_keys=True))

if __name__ == '__main__':
    main()
