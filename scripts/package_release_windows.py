#!/usr/bin/env python3
"""Package a fresh portable release without private recovery or Python requirements."""
from pathlib import Path
import argparse, hashlib, json, os, shutil, subprocess, zipfile
root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--build', type=Path, default=root / 'dist/embedded-full')
parser.add_argument('--output', type=Path, default=root / 'dist/releases')
args = parser.parse_args()
version = (root / 'VERSION').read_text().strip()
folder = args.output / ('Cardinal-3D-' + version + '-Windows-x64')
folder.mkdir(parents=True, exist_ok=False)
shutil.copytree(args.build / 'Cardinal', folder / 'Cardinal', ignore=shutil.ignore_patterns('.git', '.gitmodules', '.gitignore'))
shutil.copytree(args.build / 'rack', folder / 'rack', ignore=shutil.ignore_patterns('.godot', '*.vcv', '*.autosave', 'openxr_action_map.tres', 'test_rack.gd', '*.log'))
shutil.copytree(root / 'legal', folder / 'legal')
shutil.copytree(root / 'docs/images', folder / 'docs/images')
for filename in ('MANUAL.md', 'MANUAL.html', 'BUILDING-0.77.md', 'RELEASE-0.77.md', 'DEVELOPMENT.md'):
    shutil.copy2(root / 'docs' / filename, folder / 'docs' / filename)
shutil.copy2(root / 'README.md', folder / 'README.md')
shutil.copy2(root / 'LICENSE', folder / 'LICENSE')
shutil.copy2(root / 'upstream.lock.json', folder / 'upstream.lock.json')
shutil.copy2(root / '.tools/Godot/Godot_v4.5.1-stable_win64.exe', folder / 'Cardinal-3D.exe')
# Runtime builds cannot import a PNG on first launch. Generate this copy's
# cache now, retaining only runtime imports/classes, not personal editor state.
subprocess.run([str((folder/'Cardinal-3D.exe').resolve()), '--headless', '--audio-driver', 'Dummy', '--path', str((folder/'rack').resolve()), '--editor', '--quit-after', '60', '--frame-delay', '100'], check=True, timeout=60, capture_output=True)
editor_state = (folder/'rack/.godot/editor').resolve()
if editor_state.is_relative_to(folder.resolve()) and editor_state.exists(): shutil.rmtree(editor_state)
for xr, filename in [('on', 'Launch Quest Link.bat'), ('off', 'Launch desktop.bat')]:
    text = fr'''@echo off
setlocal
cd /d "%~dp0"
set "CARDINAL_3D_EMBEDDED=1"
set "CARDINAL_3D_XR={'1' if xr == 'on' else '0'}"
set "CARDINAL_EMBEDDED_RESOURCES=%~dp0Cardinal"
set "CARDINAL_EMBEDDED_USER_DIR=%LOCALAPPDATA%\Cardinal-3D\{version}"
set "CARDINAL_EMBEDDED_PATCH="
if not exist "%CARDINAL_EMBEDDED_USER_DIR%" mkdir "%CARDINAL_EMBEDDED_USER_DIR%"
"%~dp0Cardinal-3D.exe" --path "%~dp0rack" --rendering-driver opengl3 --xr-mode {xr} --log-file "%CARDINAL_EMBEDDED_USER_DIR%\session.log"
if errorlevel 1 pause
'''
    (folder / filename).write_text(text, encoding='ascii', newline='\r\n')
(folder / 'Read the manual.bat').write_text('@echo off\r\nstart "" "%~dp0docs\\MANUAL.html"\r\n', encoding='ascii')
metadata = {'version': version, 'source_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
            'source_archive': f'Cardinal-3D-{version}-source.tar.gz', 'platform': 'Windows x64; Quest Link/OpenXR', 'files_sha256': {}}
for path in sorted(folder.rglob('*')):
    if path.is_file(): metadata['files_sha256'][path.relative_to(folder).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
(folder / 'RELEASE-MANIFEST.json').write_text(json.dumps(metadata, indent=2) + '\n')
archive_path = args.output / (folder.name + '.zip')
with zipfile.ZipFile(archive_path, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
    for path in sorted(folder.rglob('*')):
        if path.is_file(): archive.write(path, path.relative_to(args.output))
print(f'Portable Windows candidate: {archive_path} ({archive_path.stat().st_size} bytes)')
