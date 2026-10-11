#!/usr/bin/env python3
"""Stage original full-library assets and notices for the isolated engine target."""
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
source = ROOT / 'vendor/Cardinal'
destination = ROOT / 'dist/embedded/Cardinal'
resources = destination / 'resources'
manifests = resources / 'PluginManifests'
manifests.mkdir(parents=True, exist_ok=True)
shutil.copytree(source / 'src/Rack/res', resources, dirs_exist_ok=True)
templates = resources / 'patches/templates'
templates.mkdir(parents=True, exist_ok=True)
(templates / 'native.vcv').write_text(json.dumps(dict(version='2.4.1', modules=[], cables=[])))
notices = ROOT / 'dist/embedded/Notices'
notices.mkdir(exist_ok=True)
shutil.copy2(source / 'LICENSE', notices / 'Cardinal-LICENSE')
# Use the pinned host's complete asset list. Several families keep artwork in
# art/, fonts/, samples/ or other folders instead of the conventional res/.
resource_list = ROOT / 'dist/embedded/resources.list'
surge_data = source / 'plugins/surgext/build/surge-data'
subprocess.check_call(['make', '-s', '--no-print-directory', '-C', str(source / 'plugins'),
    'STATIC_BUILD=true', 'PKG_CONFIG=false', 'CARDINAL_3D_PROTOTYPE=false',
    *(str(surge_data / name) for name in ('configuration.xml', 'fx_presets', 'wavetables', 'windows.wt'))])
subprocess.check_call(['make', '-s', '--no-print-directory', '-C', str(source / 'plugins'),
    'STATIC_BUILD=true', 'PKG_CONFIG=false', 'CARDINAL_3D_PROTOTYPE=false',
    '--eval=cardinal3d-resource-list:\n\t$(file >' + str(resource_list) + ',$(RESOURCE_FILES))\n\t@true',
    'cardinal3d-resource-list'])
asset_list = resource_list.read_text(encoding='utf-8')
assets = 0
for filename in asset_list.split():
    relative = Path(filename)
    if not filename: continue
    if relative.is_absolute() or '..' in relative.parts: raise RuntimeError(f'Unexpected asset path: {filename}')
    original = source / 'plugins' / relative
    target = resources / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    if original.is_dir(): shutil.copytree(original, target, dirs_exist_ok=True)
    else: shutil.copy2(original, target)
    assets += 1
count = 0
for plugin in sorted((source / 'plugins').iterdir()):
    manifest = plugin / 'plugin.json'
    if not plugin.is_dir() or not manifest.is_file(): continue
    json.loads(manifest.read_text(encoding='utf-8'))  # Fail on malformed packaged resources.
    shutil.copy2(manifest, manifests / (plugin.name + '.json'))
    for folder in ('res', 'presets'):
        if (plugin / folder).is_dir():
            shutil.copytree(plugin / folder, resources / plugin.name / folder, dirs_exist_ok=True)
    for pattern in ('*LICENSE*', '*COPYING*'):
        for license_file in plugin.glob(pattern):
            if license_file.is_file(): shutil.copy2(license_file, notices / (plugin.name + '-' + license_file.name))
    count += 1
shutil.copy2(ROOT / 'upstream.lock.json', ROOT / 'dist/embedded/upstream.lock.json')
print(f'Staged {assets} upstream-listed assets and {count} source plugin manifests; native registry coverage requires separate validation.')
