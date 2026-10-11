#!/usr/bin/env python3
"""Launch the private Windows development bundle without transporting audio."""
from pathlib import Path
import argparse
import os
import secrets
import socket
import subprocess

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--vr", action="store_true")
    args = parser.parse_args()
    if os.name != 'nt':
        raise RuntimeError('This launcher requires Windows')
    cardinal = ROOT / 'Cardinal/CardinalNative.exe'
    executables = list((ROOT / 'Godot').glob('Godot*_win64.exe'))
    if not cardinal.exists() or len(executables) != 1:
        raise RuntimeError('Extract the complete Windows development bundle first')
    # Keep another click on the launcher from starting a second audio runtime.
    session_dir = Path(os.environ['LOCALAPPDATA']) / 'Cardinal3D'
    session_dir.mkdir(parents=True, exist_ok=True)
    lock = socket.socket()
    lock.bind(('127.0.0.1', 39414))
    lock.listen(1)
    with socket.socket() as reservation:
        reservation.bind(('127.0.0.1', 0)); port = reservation.getsockname()[1]
    env = os.environ.copy()
    env.update(CARDINAL_3D_PORT=str(port), CARDINAL_3D_TOKEN=secrets.token_hex(24), CARDINAL_3D_OVERRIDES=str(ROOT / 'bridge/overrides.json'))
    if args.vr: env['CARDINAL_3D_XR'] = '1'
    native = subprocess.Popen([str(cardinal)], cwd=cardinal.parent, env=env)
    try:
        # The frontend transports no audio. Avoid initializing a second Windows
        # audio client and explicitly select the project's OpenGL renderer.
        frontend = subprocess.Popen([str(executables[0]), '--path', str(ROOT / 'godot'), '--rendering-driver', 'opengl3', '--audio-driver', 'Dummy', '--xr-mode', 'on' if args.vr else 'off'], cwd=ROOT, env=env)
        print('Cardinal 3D started. Closing the frontend leaves Cardinal audio running.', flush=True)
        frontend.wait()
        native.wait()
    except KeyboardInterrupt:
        # Leave the native patch and audio alive; close its original window normally.
        pass
    finally:
        lock.close()

if __name__ == '__main__': main()
