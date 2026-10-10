#!/usr/bin/env python3
"""Build in a space-free scratch directory because upstream Makefiles require it."""
from pathlib import Path
import argparse
import os
import subprocess
import tempfile
import sys
import json

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--full", action="store_true", help="Build the full bundled library instead of the milestone modules")
    parser.add_argument("--baseline", action="store_true", help="Build without the UI bridge for audio comparison")
    parser.add_argument("--jobs", type=int, default=6)
    args = parser.parse_args()
    subprocess.run([sys.executable, str(ROOT / "scripts/install_bridge.py")], check=True)
    build = Path(tempfile.gettempdir()) / ("cardinal3d-baseline" if args.baseline else "cardinal3d-full" if args.full else "cardinal3d-build")
    build.mkdir(exist_ok=True)
    subprocess.run(["rsync", "-a", "--exclude=.git", "--exclude=build", "--exclude=bin", str(ROOT / "vendor/Cardinal") + "/", str(build) + "/"], check=True)
    if args.baseline:
        for name in ("src/CardinalUI.cpp", "src/override/ModuleWidget.cpp"):
            original = subprocess.check_output(["git", "-C", str(ROOT / "vendor/Cardinal"), "show", "HEAD:" + name])
            (build / name).write_bytes(original)
    if not args.full:
        # The upstream welcome patch uses models outside the prototype registry.
        (build / "patches/templates/native.vcv").write_text(json.dumps({"version": "2.4.1", "modules": [], "cables": []}))
    tools = Path(tempfile.gettempdir()) / "cardinal3d-tools"
    if not tools.exists():
        tools.symlink_to(ROOT / ".tools", target_is_directory=True)
    cmake = tools / "cmake-3.31.8-macos-universal/CMake.app/Contents/bin/cmake"
    if not cmake.exists():
        raise RuntimeError("Missing workspace CMake; run scripts/bootstrap.py")
    env = os.environ.copy()
    if args.full:
        # Clang 17 diagnoses legacy optional-template syntax in Surge's UI drawing code.
        env["CXXFLAGS"] = env.get("CXXFLAGS", "") + " -Wno-missing-template-arg-list-after-template-kw"
    env["PATH"] = str(tools / "bin") + os.pathsep + str(cmake.parent) + os.pathsep + env["PATH"]
    common = [f"-j{args.jobs}", "STATIC_BUILD=true", "PKG_CONFIG=false", "WGET=curl -L --fail -O", "SHA256SUM=shasum -a 256"]
    if not args.full:
        common += ["CARDINAL_3D_PROTOTYPE=true", "NOPLUGINS=true"]
    if not args.baseline:
        common += ["CARDINAL_3D_BRIDGE=true"]
    for directory, target in [("deps", "all"), ("", "dgl"), ("plugins", "plugins.a"), ("src", "rack.a"), ("src/CardinalNative", "jack")]:
        print(f"Building {directory or 'root'} / {target}", flush=True)
        subprocess.run(["make", "-C", str(build / directory), target] + common, env=env, check=True)
    destination = ROOT / "build"
    destination.mkdir(exist_ok=True)
    (destination / ("baseline-path.txt" if args.baseline else "full-path.txt" if args.full else "cardinal-path.txt")).write_text(str(build))
    print(f"Built {build / 'bin/CardinalNative.app'}")

if __name__ == "__main__":
    main()
