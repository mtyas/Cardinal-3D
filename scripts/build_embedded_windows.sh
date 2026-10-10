#!/usr/bin/env bash
# Experimental engine DLL; does not replace or package the working VR runtime.
set -euo pipefail
cd "$(dirname "$0")/.."
root="$PWD"
python3 scripts/fetch_source.py
python3 scripts/install_bridge.py
source="$root/vendor/Cardinal"
target="$source/src/CardinalEmbedded"
mkdir -p "$target"
cp embedded/Host.cpp embedded/Host.h embedded/Makefile "$target/"
for file in CardinalPlugin.cpp CardinalCommon.cpp CardinalRemote.cpp common.cpp RemoteNanoVG.cpp RemoteWindow.cpp DistrhoPluginInfo.h; do
    ln -sf "../CardinalNative/$file" "$target/$file"
done
cd "$source"
export PAWPAW_CI=1 PAWPAW_SKIP_TESTS=1
set +u
source deps/PawPaw/local.env win64
set -u
args=(-j"${CARDINAL_3D_BUILD_JOBS:-4}" STATIC_BUILD=true PKG_CONFIG=false NOPLUGINS=true CARDINAL_3D_PROTOTYPE=true HEADLESS=true NOOPT=true)
make -C plugins plugins-headless.a "${args[@]}"
make -C src rack-headless.a "${args[@]}"
make -C src/CardinalEmbedded embedded "${args[@]}"
mkdir -p "$root/dist/embedded"
cp bin/Cardinal3DEngine.dll "$root/dist/embedded/"
cd "$root"
bindings="$root/.tools/godot-cpp"
pin=e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77
if [[ ! -d "$bindings/.git" ]]; then
    git clone --depth 1 --branch godot-4.5-stable https://github.com/godotengine/godot-cpp.git "$bindings"
fi
[[ "$(git -C "$bindings" rev-parse HEAD)" == "$pin" ]] || { echo 'Godot binding pin mismatch' >&2; exit 1; }
# Godot's bindings use std::mutex: select the POSIX MinGW compiler explicitly,
# without changing the distro's compiler alternatives or Cardinal's cached build.
compiler="$root/.tools/mingw-posix"
mkdir -p "$compiler/bin"
for tool in gcc g++; do ln -sf "/usr/bin/x86_64-w64-mingw32-$tool-posix" "$compiler/bin/x86_64-w64-mingw32-$tool"; done
for tool in ar ranlib gcc-ar gcc-ranlib windres strip; do ln -sf "/usr/bin/x86_64-w64-mingw32-$tool" "$compiler/bin/x86_64-w64-mingw32-$tool"; done
scons -C embedded -j"${CARDINAL_3D_BUILD_JOBS:-4}" platform=windows target=template_release arch=x86_64 mingw_prefix="$compiler" build_profile="$root/embedded/build_profile.json"
cp -r embedded/godot/. dist/embedded/godot/
cp dist/embedded/Cardinal3DEngine.dll dist/embedded/godot/bin/
