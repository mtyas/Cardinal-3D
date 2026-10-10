#!/usr/bin/env python3
"""Launch one local Cardinal session and its Godot view; preserve patch state on exit."""
from pathlib import Path
import argparse
import json
import os
import secrets
import signal
import socket
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--full", action="store_true", help="Use the complete bundled-library build")
    args = parser.parse_args()
    location = ROOT / "build" / ("full-path.txt" if args.full else "cardinal-path.txt")
    if not location.exists():
        raise RuntimeError("Build Cardinal first: python3 scripts/build.py")
    cardinal = Path(location.read_text().strip()) / "bin/CardinalNative.app/Contents/MacOS/CardinalNative"
    godot = ROOT / ".tools/Godot.app/Contents/MacOS/Godot"
    if not cardinal.exists() or not godot.exists():
        raise RuntimeError("Missing runtime; run bootstrap.py and build.py")
    env = os.environ.copy()
    with socket.socket() as reservation:
        reservation.bind(("127.0.0.1", 0))
        port = reservation.getsockname()[1]
    env["CARDINAL_3D_PORT"] = str(port)
    env["CARDINAL_3D_TOKEN"] = secrets.token_hex(24)
    env["CARDINAL_3D_OVERRIDES"] = str(ROOT / "bridge/overrides.json")
    processes = []
    try:
        processes.append(subprocess.Popen([str(cardinal)], env=env))
        processes.append(subprocess.Popen([str(godot), "--path", str(ROOT / "godot")], env=env))
        session = dict(port=port, token=env["CARDINAL_3D_TOKEN"], cardinal_pid=processes[0].pid, godot_pid=processes[1].pid)
        path = ROOT / "build/session.json"
        path.write_text(json.dumps(session)); path.chmod(0o600)
        print("Cardinal and Cardinal 3D launched. The original Cardinal window remains available.", flush=True)
        processes[-1].wait()
    except KeyboardInterrupt:
        pass
    finally:
        # Close the original window normally to save its autosave and settings.
        # A frontend exit leaves Cardinal running, including its audio and patch.
        if processes and processes[0].poll() is None:
            print("Cardinal is still running; close its window when you finish.")

if __name__ == "__main__":
    main()
