"""Measure the real Windows artwork bridge at a 72 Hz client polling cadence.

Uses an isolated temporary native instance and reads, but never saves, the patch.
"""
import argparse
import importlib.util
import os
from pathlib import Path
import secrets
import socket
import subprocess

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--bundle', type=Path, required=True)
    parser.add_argument('--patch', type=Path, required=True)
    parser.add_argument('--actions', action='store_true')
    parser.add_argument('--palette', action='store_true', help='Require native SVG colour metadata in the rebuilt host')
    args = parser.parse_args()
    with socket.socket() as reservation:
        reservation.bind(('127.0.0.1', 0))
        port = reservation.getsockname()[1]
    env = os.environ.copy()
    env.update(CARDINAL_3D_PORT=str(port), CARDINAL_3D_TOKEN=secrets.token_hex(24), CARDINAL_3D_OVERRIDES=str(args.bundle / 'bridge/overrides.json'), CARDINAL_3D_PROBE_PATCH=str(args.patch.resolve()))
    native = subprocess.Popen([str(args.bundle / 'Cardinal/CardinalNative.exe')], cwd=args.bundle / 'Cardinal', env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        if args.actions or args.palette:
            spec = importlib.util.spec_from_file_location('live', ROOT / 'tests/live_bridge.py')
            live = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(live)
            import time
            client = None
            for attempt in range(60):
                try:
                    client = live.Client(port, env['CARDINAL_3D_TOKEN'])
                    break
                except OSError:
                    time.sleep(0.25)
            if client is None:
                raise RuntimeError('Scratch native host did not start')
            try:
                client.wait(lambda s: True)
                client.cmd('starter')
                state = client.wait(lambda s: len(s['modules']) == 6)
                vco = next(m for m in state['modules'] if m['model'] == 'VCO')
                scope = next(m for m in state['modules'] if m['model'] == 'Scope')
                if args.actions:
                    live.verify_vr_actions(client, vco, scope)
                if args.palette:
                    import re
                    state = client.wait(lambda s: any(c.get('body_color') for m in s['modules']
                                                      for c in m.get('controls', [])))
                    colours = [c['body_color'] for m in state['modules'] for c in m.get('controls', [])
                               if c.get('kind') == 'knob' and c.get('body_color')]
                    if not colours or not all(re.fullmatch(r'#[0-9a-f]{6}', color) for color in colours):
                        raise AssertionError('Native SVG palette metadata missing or invalid')
                    print(f'PASS: native original SVG colours supplied for {len(colours)} starter knobs')
                return 0
            finally:
                client.peer.close()
        console = next((args.bundle / 'Godot').glob('*_win64_console.exe'))
        result = subprocess.run([str(console), '--headless', '--audio-driver', 'Dummy', '--path', str(ROOT / 'godot'), '--script', str(ROOT / 'tests/frontend_live_stream.gd')], env=env, capture_output=True, text=True, timeout=45)
        print(result.stdout + result.stderr, end='')
        return result.returncode
    finally:
        # This test instance has no user edits or writes to the supplied patch.
        native.terminate()
        native.wait(timeout=10)

if __name__ == '__main__':
    raise SystemExit(main())
