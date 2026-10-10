#!/usr/bin/env python3
"""Fetch pinned source and workspace-local build tools. Nothing is installed system-wide."""
from pathlib import Path
import json
import os
import subprocess
import tempfile
import shutil

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / ".tools"

def run(*args, cwd=None, env=None):
    subprocess.run(args, cwd=cwd, env=env, check=True)

def download(url, path):
    if not path.exists():
        run("curl", "-L", "--fail", "--silent", "--show-error", url, "-o", str(path))

def main():
    TOOLS.mkdir(exist_ok=True)
    pin = json.loads((ROOT / "upstream.lock.json").read_text())
    source = ROOT / "vendor/Cardinal"
    if not source.exists():
        run("git", "clone", pin["repository"], str(source))
    actual = subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
    if actual != pin["commit"]:
        if subprocess.check_output(["git", "-C", str(source), "status", "--porcelain"], text=True):
            raise RuntimeError("Checkout differs from the pin and has local changes; preserve them before updating")
        run("git", "-C", str(source), "checkout", "--detach", pin["commit"])
    run("git", "-C", str(source), "submodule", "update", "--init", "--recursive", "--jobs", "8")
    download("https://github.com/godotengine/godot/releases/download/4.5.1-stable/Godot_v4.5.1-stable_macos.universal.zip", TOOLS / "godot.zip")
    if not (TOOLS / "Godot.app").exists():
        run("unzip", "-q", str(TOOLS / "godot.zip"), "-d", str(TOOLS))
    (TOOLS / "Godot.app/Contents/MacOS/_sc_").touch()
    download("https://github.com/Kitware/CMake/releases/download/v3.31.8/cmake-3.31.8-macos-universal.tar.gz", TOOLS / "cmake.tar.gz")
    if not (TOOLS / "cmake-3.31.8-macos-universal").exists():
        run("tar", "-xzf", str(TOOLS / "cmake.tar.gz"), "-C", str(TOOLS))
    alias = Path(tempfile.gettempdir()) / "cardinal3d-tools"
    if not alias.exists():
        alias.symlink_to(TOOLS, target_is_directory=True)
    env = os.environ.copy()
    env["PATH"] = str(alias / "bin") + os.pathsep + env["PATH"]
    for name, version in [("autoconf", "2.71"), ("automake", "1.16.5"), ("libtool", "2.4.7")]:
        executable = alias / "bin" / ("libtoolize" if name == "libtool" else name)
        if executable.exists():
            continue
        archive = TOOLS / f"{name}-{version}.tar.gz"
        download(f"https://ftp.gnu.org/gnu/{name}/{archive.name}", archive)
        sources = Path(tempfile.gettempdir()) / "cardinal3d-tool-sources"
        sources.mkdir(exist_ok=True)
        run("tar", "-xzf", str(archive), "-C", str(sources))
        directory = sources / f"{name}-{version}"
        run("./configure", f"--prefix={alias}", cwd=directory, env=env)
        run("make", "-j4", cwd=directory, env=env)
        run("make", "install", cwd=directory, env=env)
    # Speex's configure.ac needs pkg.m4 even with optional FFT support disabled.
    macro_archive = TOOLS / "pkg-config-0.29.2.tar.gz"
    download("https://pkgconfig.freedesktop.org/releases/pkg-config-0.29.2.tar.gz", macro_archive)
    sources = Path(tempfile.gettempdir()) / "cardinal3d-tool-sources"
    sources.mkdir(exist_ok=True)
    run("tar", "-xzf", str(macro_archive), "-C", str(sources))
    macro_dir = TOOLS / "share/aclocal"
    macro_dir.mkdir(parents=True, exist_ok=True)
    macro = (sources / "pkg-config-0.29.2/pkg.m4.in").read_text().replace("@VERSION@", "0.29.2")
    (macro_dir / "pkg.m4").write_text(macro)
    print("Workspace toolchain ready. Run python3 scripts/build.py")

if __name__ == "__main__":
    main()
