#!/usr/bin/env python3
"""Compare eight owner-thread updates with one ordered batch; not XR latency."""
import argparse
import ctypes as c
import json
from pathlib import Path
import statistics
import tempfile
import time

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--build', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    build = args.build.resolve()
    dll = c.CDLL(str(build / 'Cardinal3DEngine.dll'))
    dll.c3d_create.argtypes = [c.c_char_p, c.c_char_p, c.c_double, c.c_uint32]
    dll.c3d_create.restype = c.c_void_p
    dll.c3d_destroy.argtypes = [c.c_void_p]
    dll.c3d_messages_json.argtypes = [c.c_void_p, c.c_char_p]
    dll.c3d_messages_json.restype = c.c_char_p
    with tempfile.TemporaryDirectory(prefix='cardinal-command-benchmark-') as user:
        host = dll.c3d_create(str(build / 'Cardinal').encode(), user.encode(), 48000, 256)
        assert host
        try:
            def invoke(message):
                raw = dll.c3d_messages_json(host, json.dumps(message).encode() if message is not None else b'')
                assert raw
                result = json.loads(raw)
                assert all(m.get('ok', True) for m in result if m['type'] == 'ack'), result
                return result
            hello = invoke(dict(op='hello', version=1, request=1))
            generation = next(m['generation'] for m in hello if m['type'] == 'snapshot')
            invoke(dict(op='starter', request=2, generation=generation))
            commands = [dict(op='heartbeat', request=10+i) for i in range(8)]
            samples = {'separate': [], 'batch': []}
            # Interleave modes to avoid comparing only cold vs warmed caches.
            for frame in range(100):
                for mode in ('separate', 'batch') if frame % 2 else ('batch', 'separate'):
                    started = time.perf_counter()
                    if mode == 'separate':
                        for command in commands: invoke(command)
                        invoke(None)  # Previous frontend's extra snapshot poll.
                    else: invoke(commands)
                    if frame >= 10: samples[mode].append((time.perf_counter()-started)*1000)
            report = dict(commands_per_frame=8, patch='six-module native starter',
                          audio_running=False, headset_latency_measurement=False,
                          median_ms={mode: statistics.median(values) for mode, values in samples.items()})
            report['reduction_percent'] = 100*(1-report['median_ms']['batch']/report['median_ms']['separate'])
            args.report.parent.mkdir(parents=True, exist_ok=True)
            args.report.write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8')
            print(json.dumps(report))
        finally: assert dll.c3d_destroy(host)

if __name__ == '__main__': main()
