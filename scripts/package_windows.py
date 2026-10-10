#!/usr/bin/env python3
"""Create a private Windows development bundle from the cross-compiled runtime."""
from pathlib import Path
import argparse
import json
import shutil
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PLUGINS = ('Cardinal', 'Fundamental', 'AudibleInstruments', 'Befaco', 'BogaudioModules')

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--reuse-runtime', type=Path)
    args = parser.parse_args()
    destination = ROOT / 'dist/Cardinal-3D-Windows'
    if destination.exists():
        shutil.rmtree(destination)
    if args.reuse_runtime:
        previous = args.reuse_runtime
        if json.loads((previous / 'upstream.lock.json').read_text()) != json.loads((ROOT / 'upstream.lock.json').read_text()):
            raise RuntimeError('Runtime dependency pins do not match')
        native = previous / 'Cardinal/CardinalNative.exe'
        if native.read_bytes()[:2] != b'MZ':
            raise RuntimeError('Previous artifact has no Windows runtime')
        shutil.copytree(previous / 'Cardinal', destination / 'Cardinal')
        shutil.copytree(previous / 'Notices', destination / 'Notices')
        notices = destination / 'Notices'
    else:
        source = ROOT / 'vendor/Cardinal'
        native = source / 'bin/CardinalNative.exe'
        if not native.exists() or native.read_bytes()[:2] != b'MZ':
            raise RuntimeError('Build the Windows CardinalNative.exe first')
        (destination / 'Cardinal/resources/PluginManifests').mkdir(parents=True)
        shutil.copy2(native, destination / 'Cardinal/CardinalNative.exe')
        resources = destination / 'Cardinal/resources'
        shutil.copytree(source / 'src/Rack/res', resources / 'res')
        templates = resources / 'patches/templates'
        templates.mkdir(parents=True)
        (templates / 'native.vcv').write_text(json.dumps(dict(version='2.4.1', modules=[], cables=[])))
        notices = destination / 'Notices'
        notices.mkdir()
        shutil.copytree(source / 'docs', notices / 'Cardinal')
        shutil.copy2(source / 'LICENSE', notices / 'Cardinal-LICENSE')
        for name in PLUGINS:
            plugin = source / 'plugins' / name
            shutil.copy2(plugin / 'plugin.json', resources / 'PluginManifests' / (name + '.json'))
            for folder in ('res', 'presets'):
                if (plugin / folder).exists():
                    shutil.copytree(plugin / folder, resources / name / folder)
            for license_file in plugin.glob('*LICENSE*'):
                if license_file.is_file():
                    shutil.copy2(license_file, notices / (name + '-' + license_file.name))
    # Keep development files; exclude user patches, imports and local state.
    shutil.copytree(ROOT / 'godot', destination / 'godot', ignore=shutil.ignore_patterns('.godot', '*.vcv', '*.autosave', 'tests'))
    (destination / 'bridge').mkdir()
    shutil.copy2(ROOT / 'bridge/overrides.json', destination / 'bridge/overrides.json')
    (destination / 'scripts').mkdir()
    shutil.copy2(ROOT / 'scripts/run_windows.py', destination / 'scripts/run_windows.py')
    shutil.copy2(ROOT / 'LICENSE', destination / 'LICENSE')
    shutil.copy2(ROOT / 'upstream.lock.json', destination / 'upstream.lock.json')
    shutil.copy2(ROOT / 'docs/ARTWORK.md', notices / 'ARTWORK.md')
    version = json.loads((ROOT / 'upstream.lock.json').read_text())['godot']
    tools = ROOT / '.tools'
    tools.mkdir(exist_ok=True)
    archive = tools / 'godot-windows.zip'
    if not archive.exists():
        urllib.request.urlretrieve(f'https://github.com/godotengine/godot/releases/download/{version}/Godot_v{version}_win64.exe.zip', archive)
    (destination / 'Godot').mkdir()
    with zipfile.ZipFile(archive) as bundle:
        bundle.extractall(destination / 'Godot')
    (destination / 'Launch Cardinal 3D.bat').write_text('@echo off\r\ncd /d "%~dp0"\r\npy -3 scripts\\run_windows.py\r\nif errorlevel 1 pause\r\n')
    (destination / 'Launch Cardinal 3D VR.bat').write_text('@echo off\r\ncd /d "%~dp0"\r\npy -3 scripts\\run_windows.py --vr\r\nif errorlevel 1 pause\r\n')
    (destination / 'README.txt').write_text('Private Windows development build. Install Python 3, extract the complete folder, then run Launch Cardinal 3D.bat.\nChoose a native audio device in the original Cardinal window. Closing Godot leaves audio running.\nFor VR, connect Quest Link, select the Meta OpenXR runtime, and run Launch Cardinal 3D VR.bat. Point and pinch to operate controls and wires; controller triggers are the fallback. Physical headset validation remains required. See docs/WINDOWS.md in the private repository.\nSource: https://github.com/mtyas/Cardinal-3D (private), pinned dependencies in upstream.lock.json.\nPreserve Notices and artwork restrictions; this bundle is not cleared for public distribution.\n')
    print(shutil.make_archive(str(destination), 'zip', destination.parent, destination.name))

if __name__ == '__main__': main()
