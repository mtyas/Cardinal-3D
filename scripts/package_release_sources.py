#!/usr/bin/env python3
"""Create a recursive matching source archive, not GitHub's incomplete gitlink ZIP."""
from pathlib import Path
import argparse, hashlib, io, json, os, subprocess, tarfile
root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--cardinal', type=Path, required=True)
parser.add_argument('--bindings', type=Path, required=True)
parser.add_argument('--downloads', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
version = (root / 'VERSION').read_text().strip()
prefix = 'Cardinal-3D-' + version + '-source'
def git(directory, *arguments):
    return subprocess.check_output(['git', '-c', 'safe.directory=' + str(directory), '-C', str(directory), *arguments])
def tracked(directory, recursive=True):
    files = set()
    repositories = [directory]
    for current, directories, filenames in os.walk(directory) if recursive else []:
        if Path(current) != directory and '.git' in filenames: repositories.append(Path(current))
        directories[:] = [d for d in directories if d not in ('.git', 'build', 'bin', 'node_modules')]
    for repository in repositories:
        for filename in git(repository, 'ls-files', '-z').decode().split('\0'):
            path = repository / filename
            if filename and path.is_file(): files.add(path)
    return sorted(files)
args.output.parent.mkdir(parents=True, exist_ok=True)
manifest = {'project_commit': git(root, 'rev-parse', 'HEAD').decode().strip(), 'version': version, 'repositories': {}, 'archives': {}}
with tarfile.open(args.output, 'w:gz', compresslevel=5, dereference=True) as archive:
    def metadata(name, content):
        data = content.encode(); info = tarfile.TarInfo(prefix + '/' + name); info.size = len(data); info.mode = 0o644
        archive.addfile(info, io.BytesIO(data))
    for directory, destination in [(root, ''), (args.cardinal, 'vendor/Cardinal/'), (args.bindings, '.tools/godot-cpp/')]:
        hashes = {}
        for path in tracked(directory, recursive=directory != root):
            relative = path.relative_to(directory).as_posix()
            if directory == root and relative.startswith(('setup/', 'vendor/')): continue
            archive.add(path, arcname=prefix + '/' + destination + relative, recursive=False)
            hashes[relative] = hashlib.sha256(path.read_bytes()).hexdigest()
        commit = git(directory, 'rev-parse', 'HEAD').decode().strip()
        manifest['repositories'][destination or 'project'] = {'commit': commit, 'files': len(hashes)}
        if directory == args.cardinal:
            metadata(destination + '.source-snapshot.json', json.dumps({'commit': commit, 'sha256': hashes}))
            metadata(destination + '.source-original-plugins-Makefile', git(directory, 'show', 'HEAD:plugins/Makefile').decode())
        if directory == args.bindings: metadata(destination + '.source-pin', commit + '\n')
    for path in sorted(args.downloads.iterdir()):
        if path.is_file():
            archive.add(path, arcname=prefix + '/dependency-sources/' + path.name, recursive=False)
            manifest['archives'][path.name] = hashlib.sha256(path.read_bytes()).hexdigest()
    metadata('SOURCE_MANIFEST.json', json.dumps(manifest, indent=2) + '\n')
print(json.dumps({'source_archive': str(args.output), 'bytes': args.output.stat().st_size, **manifest['repositories']}))
