#!/usr/bin/env python3
"""Instantiate every native model read-only and audit original 3D descriptors."""
import argparse
import ctypes as c
import json
from pathlib import Path
import tempfile
import time

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--dll', type=Path, required=True)
    parser.add_argument('--resources', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--minimum-models', type=int, default=190)
    args = parser.parse_args()
    dll = c.CDLL(str(args.dll.resolve()))
    dll.c3d_create.argtypes = [c.c_char_p, c.c_char_p, c.c_double, c.c_uint32]
    dll.c3d_create.restype = c.c_void_p
    dll.c3d_destroy.argtypes = [c.c_void_p]
    dll.c3d_messages_json.argtypes = [c.c_void_p, c.c_char_p]
    dll.c3d_messages_json.restype = c.c_char_p
    dll.c3d_error.argtypes = [c.c_void_p]
    dll.c3d_error.restype = c.c_char_p
    args.report = args.report.resolve()
    args.report.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='cardinal-model-audit-') as scratch:
        host = dll.c3d_create(str(args.resources.resolve()).encode(), scratch.encode(), 48000, 256)
        assert host, dll.c3d_error(None)
        healthy = True
        try:
            def invoke(request):
                raw = dll.c3d_messages_json(host, json.dumps(request).encode() if request else b'')
                assert raw, dll.c3d_error(host)
                messages = json.loads(raw)
                for message in messages:
                    if message['type'] == 'ack': assert message['ok'], message
                return messages
            hello = invoke(dict(op='hello', version=1, request=1))
            catalog = next(m['models'] for m in hello if m['type'] == 'catalog')
            state = next(m for m in hello if m['type'] == 'snapshot')
            assert len(catalog) >= args.minimum_models, len(catalog)
            started = time.perf_counter()
            messages = invoke(dict(op='describe_library', request=2, generation=state['generation'], path=str(args.report)))
            done = False
            for _ in range(len(catalog) + 3):
                if any(m['type'] == 'ack' and m['request'] == 2 for m in messages):
                    done = True
                    break
                try:
                    messages = invoke(None)
                except OSError as error:
                    healthy = False
                    current = catalog[min(_, len(catalog) - 1)]
                    raise RuntimeError(f'Native factory failed near {current}: {error}') from error
            assert done and args.report.is_file(), 'Native scan did not complete'
            report = json.loads(args.report.read_text(encoding='utf-8'))
            modules = report['modules']
            errors = [m for m in modules if 'error' in m]
            assert len(modules) == len(catalog) and not errors, errors
            knobs = [p for m in modules for p in m['descriptor']['controls'] if p['kind'] == 'knob']
            summary = dict(result='PASS', models=len(modules), plugins=len({m['plugin'] for m in modules}),
                knob_controls=len(knobs), original_knob_colours=sum(bool(p.get('body_color')) for p in knobs),
                custom_controls=sum(p['kind'] == 'custom' for m in modules for p in m['descriptor']['controls']),
                seconds=round(time.perf_counter() - started, 2), attached_to_audio=False)
            args.report.with_suffix('.summary.json').write_text(json.dumps(summary, indent=2), encoding='utf-8')
            print(json.dumps(summary), flush=True)
        finally:
            if healthy: assert dll.c3d_destroy(host)

if __name__ == '__main__': main()
