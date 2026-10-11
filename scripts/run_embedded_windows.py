#!/usr/bin/env python3
"""Launch the isolated Windows/Quest embedded host; never spawn Cardinal.exe."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]

def meta_runtime():
    candidates = [Path(os.environ.get('ProgramFiles', 'C:/Program Files')) / name /
        'Support/oculus-runtime/oculus_openxr_64.json' for name in ('Meta Horizon', 'Oculus')]
    try:
        import winreg
        with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, r'SOFTWARE\Oculus VR, LLC\Oculus') as key:
            candidates.insert(0, Path(winreg.QueryValueEx(key, 'Base')[0]) / 'Support/oculus-runtime/oculus_openxr_64.json')
    except OSError: pass
    runtime = next((path for path in candidates if path.is_file()), None)
    if runtime is None: raise RuntimeError('Meta Horizon Link runtime not found')
    return runtime

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--vr', action='store_true')
    parser.add_argument('--build', type=Path, help='Explicit development build; otherwise use the saved launch copy')
    parser.add_argument('--godot', type=Path)
    parser.add_argument('--patch', type=Path)
    parser.add_argument('--user-directory', type=Path, default=ROOT.parent / 'standalone-user')
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    if args.build is None:
        pointer = ROOT.parent / 'standalone-runtime.json'
        if not pointer.is_file(): raise RuntimeError('Run Build standalone locally.bat to prepare a launch copy')
        build = Path(json.loads(pointer.read_text(encoding='utf-8'))['runtime']).resolve()
    else:
        build = args.build.resolve()
    version = json.loads((ROOT / 'upstream.lock.json').read_text(encoding='utf-8'))['godot']
    godot = args.godot or ROOT / '.tools/Godot' / f'Godot_v{version}_win64_console.exe'
    for required in (godot, build / 'Cardinal/resources/PluginManifests/Cardinal.json',
                     build / 'rack/project.godot', build / 'rack/bin/Cardinal3DEngine.dll',
                     build / 'rack/bin/Cardinal3DExtension.dll'):
        if not required.is_file(): raise RuntimeError(f'Standalone test is not built yet: {required}')
    env = os.environ.copy()
    env['CARDINAL_3D_EMBEDDED'] = '1'
    env['CARDINAL_EMBEDDED_RESOURCES'] = str(build / 'Cardinal')
    env['CARDINAL_EMBEDDED_USER_DIR'] = str(args.user_directory.resolve())
    env.pop('CARDINAL_EMBEDDED_PATCH', None)
    patch = args.patch
    # Seed only the first launch from the user's last saved rack, read-only.
    if patch is None and not (args.user_directory / 'autosave.vcv').is_file():
        saved = ROOT.parent / 'Quest starter.vcv'
        if saved.is_file(): patch = saved
    if patch is not None:
        if not patch.is_file(): raise RuntimeError(f'Patch not found: {patch}')
        env['CARDINAL_EMBEDDED_PATCH'] = str(patch.resolve())
    env['CARDINAL_3D_XR'] = '1' if args.vr else '0'
    if args.vr: env['XR_RUNTIME_JSON'] = str(meta_runtime())
    command = [str(godot.resolve()), '--path', str(build / 'rack'),
        '--rendering-driver', 'opengl3', '--xr-mode', 'on' if args.vr else 'off']
    print('Standalone test: Cardinal engine and audio inside one Godot process.', flush=True)
    print(f'Patch recovery and audio settings: {args.user_directory.resolve()}', flush=True)
    if args.vr: print('Connect Quest Link before starting this test.', flush=True)
    if args.dry_run:
        print('PASS: launcher paths and Meta runtime validated; no app started.', flush=True)
        return 0
    return subprocess.call(command, cwd=build, env=env)

if __name__ == '__main__':
    try: sys.exit(main())
    except Exception as error:
        print(f'Setup needed: {error}', file=sys.stderr)
        sys.exit(1)
