# Building Cardinal 3D 0.77 locally

The Windows download is ready to run. Building is for contributors; it does not require Docker. Windows binaries are cross-compiled with MinGW on Linux/WSL, then run with Godot 4.5.1 and Quest Link on Windows.

## Matching source

Use **Cardinal-3D-0.77-source.tar.gz** from the same release as the binary. It contains the Cardinal-3D project, the exact recursive Cardinal modules and UI/build modifications, godot-cpp sources, cached dependency source archives and `SOURCE_MANIFEST.json`. The automatic GitHub source ZIP contains only this repository and does not include all dependencies.

Extract under a Linux filesystem path without spaces, for example `~/cardinal3d`. The archive's Cardinal snapshot verifies its files before applying the idempotent UI/build overlay. Original Cardinal's plugin Makefile is retained for the overlay generator. No private patch, settings, cache or Git credentials are included.

## Linux / WSL toolchain

Use a Linux/WSL environment with Python 3, Git, Make, rsync, SCons and the POSIX MinGW x64 compiler. Cardinal's pinned PawPaw bootstrap supplies its library dependencies. Network access is needed for system build tools and any dependencies not already cached. Copy `dependency-sources/*` into PawPaw's download cache (`~/PawPawBuilds/downloads`) before bootstrapping to reuse the provided sources.

From the extracted project directory:

```sh
python3 scripts/fetch_source.py
cd vendor/Cardinal
export PAWPAW_CI=1 PAWPAW_SKIP_TESTS=1
export PAWPAW_SKIP_QT=1 PAWPAW_SKIP_LTO=1 PAWPAW_FAST_MATH=1
export PAWPAW_SKIP_GLIB=1 PAWPAW_SKIP_LV2=1 PAWPAW_SKIP_OPENSSL=1 PAWPAW_SKIP_SAMPLERATE=1
./deps/PawPaw/.github/workflows/bootstrap-deps.sh win64
./deps/PawPaw/bootstrap-common.sh win64
./deps/PawPaw/bootstrap-plugins.sh win64
cd ../..
export CARDINAL_EMBEDDED_FULL=1 CARDINAL_EMBEDDED_GRAPHICS=1
export CARDINAL_3D_BUILD_JOBS=4
bash scripts/build_embedded_windows.sh
```

The output is `dist/embedded`. Copy it to Windows, keep its Cardinal/rack folders together, and use the pinned Godot Windows executable. Set `CARDINAL_3D_EMBEDDED=1`, `CARDINAL_EMBEDDED_RESOURCES` to the Cardinal directory, and `CARDINAL_EMBEDDED_USER_DIR` to a separate settings directory. `CARDINAL_3D_XR=1` enables Quest/OpenXR mode. See the release's launchers for exact invocation. Bundled Godot's MIT licence and complete third-party notices must accompany its executable.

The development PC's cached build uses `scripts/build_local_windows.ps1 -FullRegistry`, with WSL distribution `Cardinal3DBuild`. This named distribution is a local setup, not included in the public ZIP. For a fresh contributor machine, use the Linux/WSL instructions above. Rebuilding from a Git checkout instead of the complete archive fetches exact commits from `upstream.lock.json` and recursively checks out submodules; godot-cpp is pinned in the build script.

## Validation and redistribution

On Windows, run `scripts/check_embedded.py --graphics` with the build, resources and pinned Godot paths; it checks native DSP/audio, patch/history, artwork, embedded UI and recovery. Frontend interaction checks live under `tests/frontend_*.gd`. Physical headset acceptance remains necessary for comfort, visual quality and controller feel.

`scripts/package_release_sources.py` and `scripts/package_release_windows.py` produce matching public candidates. Preserve `LICENSE`, the complete `legal`/`Licences` directory, the source archive and all upstream asset terms. Review `legal/NOTICE.txt` and Cardinal's artwork/permission tables before commercial artwork reuse. Do not ship the private `standalone-user` folder or personal .vcv patches.
