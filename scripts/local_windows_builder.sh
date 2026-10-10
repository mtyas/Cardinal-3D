#!/usr/bin/env bash
set -euo pipefail
source_path="$1"
jobs="${2:-4}"
mkdir -p /root/cardinal3d
# Keep make inputs off the Windows filesystem and retain all dependency caches.
rsync -a --exclude=.git --exclude=vendor --exclude=build --exclude=dist \
    --exclude=.tools --exclude=setup --exclude=.godot --exclude=__pycache__ \
    "$source_path/" /root/cardinal3d/
cd /root/cardinal3d
sed -i 's/\r$//' scripts/*.sh
if [[ "${3:-False}" == True ]]; then exit 0; fi
CARDINAL_3D_BUILD_JOBS="$jobs" CARDINAL_3D_INSTALL_BUILD_DEPS=1 bash scripts/build_windows.sh
mkdir -p "$source_path/dist"
# Windows merges Godot/ and godot/ names; copy the zip instead of the Linux tree.
cp dist/Cardinal-3D-Windows.zip "$source_path/dist/"
