#!/usr/bin/env bash
# Linux -> Windows x64, using Cardinal's pinned upstream PawPaw toolchain.
set -euo pipefail
cd "$(dirname "$0")/.."
project_root="$PWD"
if [[ "$project_root" == *' '* ]]; then
    echo 'Use a checkout path without spaces for the upstream Makefiles.' >&2
    exit 1
fi
python3 scripts/fetch_source.py
python3 scripts/install_bridge.py
cd vendor/Cardinal
export PAWPAW_SKIP_QT=1 PAWPAW_SKIP_LTO=1 PAWPAW_FAST_MATH=1
# A local WSL builder is noninteractive, just like the hosted cross compiler.
# Avoid Wine onboarding and executing foreign-platform dependency test programs.
export PAWPAW_CI=1 PAWPAW_SKIP_TESTS=1
export PAWPAW_SKIP_GLIB=1 PAWPAW_SKIP_LV2=1 PAWPAW_SKIP_OPENSSL=1 PAWPAW_SKIP_SAMPLERATE=1
if [[ "${CARDINAL_3D_INSTALL_BUILD_DEPS:-0}" == 1 ]]; then
    ./deps/PawPaw/.github/workflows/bootstrap-deps.sh win64
fi
./deps/PawPaw/bootstrap-common.sh win64
./deps/PawPaw/bootstrap-plugins.sh win64
# The upstream environment references optional variables; source outside nounset.
set +u
source deps/PawPaw/local.env win64
set -u
# Match the prototype's macOS build: optional pkg-config libraries (notably
# FFTW/aubio) are outside this registry and must not become link prerequisites.
build_args=(-j"${CARDINAL_3D_BUILD_JOBS:-4}" STATIC_BUILD=true PKG_CONFIG=false NOPLUGINS=true CARDINAL_3D_PROTOTYPE=true CARDINAL_3D_BRIDGE=true NOOPT=true)
make -C deps all "${build_args[@]}"
make dgl "${build_args[@]}"
make -C plugins plugins.a "${build_args[@]}"
make -C src rack.a "${build_args[@]}"
make -C src/CardinalNative jack "${build_args[@]}"
cd "$project_root"
python3 scripts/package_windows.py
