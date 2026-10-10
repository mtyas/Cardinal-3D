#!/usr/bin/env python3
"""Exercise the real Windows DSP library inside this Python process, without TCP/UI."""
import argparse
import ctypes as c
import json
import math
import os
from pathlib import Path
import tempfile
import threading
import time

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--dll', type=Path, required=True)
    parser.add_argument('--resources', type=Path, required=True, help='Portable Cardinal folder')
    args = parser.parse_args()
    dll = c.CDLL(str(args.dll.resolve()))
    dll.c3d_create.argtypes = [c.c_char_p, c.c_char_p, c.c_double, c.c_uint32]
    dll.c3d_create.restype = c.c_void_p
    dll.c3d_destroy.argtypes = [c.c_void_p]
    dll.c3d_error.argtypes = [c.c_void_p]
    dll.c3d_error.restype = c.c_char_p
    for name in ('load', 'save'):
        fn = getattr(dll, 'c3d_' + name)
        fn.argtypes = [c.c_void_p, c.c_char_p]
        fn.restype = c.c_int
    dll.c3d_patch_json.argtypes = [c.c_void_p]
    dll.c3d_patch_json.restype = c.c_char_p
    dll.c3d_messages_json.argtypes = [c.c_void_p, c.c_char_p]
    dll.c3d_messages_json.restype = c.c_char_p
    dll.c3d_panel_rgba.argtypes = [c.c_void_p, c.c_char_p, c.POINTER(c.c_uint32), c.POINTER(c.c_uint32)]
    dll.c3d_panel_rgba.restype = c.POINTER(c.c_uint8)
    fp = c.POINTER(c.c_float)
    dll.c3d_process.argtypes = [c.c_void_p, fp, fp, fp, fp, c.c_uint32]
    dll.c3d_process.restype = c.c_int
    resources = str(args.resources.resolve()).encode()
    user = tempfile.TemporaryDirectory(prefix='cardinal-embedded-settings-')
    user_path = user.name.encode()
    assert not dll.c3d_create(resources, user_path, 0, 256)
    host = dll.c3d_create(resources, user_path, 48000, 256)
    assert host, dll.c3d_error(None)
    try:
        assert not dll.c3d_create(resources, user_path, 48000, 256), 'Second instance must be rejected'
        with tempfile.TemporaryDirectory(prefix='cardinal-embedded-') as scratch:
            source, saved = Path(scratch) / 'tone.vcv', Path(scratch) / 'roundtrip.vcv'
            source.write_text(json.dumps(dict(version='2.4.1', modules=[
                dict(id=1, plugin='Fundamental', model='VCO', version='2.6.4', pos=[0, 0], params=[]),
                dict(id=2, plugin='Cardinal', model='HostAudio2', version='26.02', pos=[10, 0], params=[]),
            ], cables=[dict(id=3, outputModuleId=1, outputId=0, inputModuleId=2, inputId=0,
                            color='#ff5252')])) , encoding='utf-8')
            assert dll.c3d_load(host, str(source).encode()), dll.c3d_error(host)
            before = json.loads(dll.c3d_patch_json(host))
            assert len(before['modules']) == 2 and len(before['cables']) == 1, before
            assert not dll.c3d_load(host, str(Path(scratch) / 'missing.vcv').encode())
            assert before == json.loads(dll.c3d_patch_json(host)), 'Missing file must preserve patch'
            state = {}
            def command(op, **data):
                nonlocal state
                request = dict(op=op, request=1, generation=state.get('generation', ''), **data)
                response = dll.c3d_messages_json(host, json.dumps(request).encode())
                assert response, dll.c3d_error(host)
                messages = json.loads(response)
                ack = next(m for m in messages if m['type'] == 'ack')
                assert ack['ok'], ack
                state = next(m for m in reversed(messages) if m['type'] == 'snapshot')
                return messages
            hello = command('hello', version=1)
            catalog = next(m for m in hello if m['type'] == 'catalog')
            assert len(catalog['models']) == 190
            assert len(state['modules']) == 2 and len(state['cables']) == 1
            vco = next(m for m in state['modules'] if m['model'] == 'VCO')
            assert any(p.get('body_color') for p in vco['controls'] if p['kind'] == 'knob')
            cable = state['cables'][0]
            command('disconnect_cable', cable_id=cable['id'], input_module=cable['input_module'], input_port=cable['input_port'])
            assert not state['cables']
            command('undo')
            assert len(state['cables']) == 1
            command('add', plugin='Fundamental', model='VCA-1')
            assert len(state['modules']) == 3
            command('undo')
            assert len(state['modules']) == 2
            out_l, out_r = (c.c_float * 256)(), (c.c_float * 256)()
            assert not dll.c3d_process(host, None, None, out_l, out_r, 257)
            assert not dll.c3d_process(host, None, None, None, out_r, 256)
            energy, peak = 0., 0.
            started = time.perf_counter()
            for _ in range(375):  # Two seconds of offline audio, no device touched.
                assert dll.c3d_process(host, None, None, out_l, out_r, 256)
                assert all(math.isfinite(v) for v in out_l) and all(math.isfinite(v) for v in out_r)
                energy += sum(v*v for v in out_l)
                peak = max(peak, max(abs(v) for v in out_l))
            elapsed = time.perf_counter() - started
            rms = math.sqrt(energy / 96000)
            assert rms > .01 and peak <= 1.01, (rms, peak)
            # UI work must never manufacture silent blocks on the DSP thread.
            # All native widget access stays on the owner thread, as upstream.
            running, ready = threading.Event(), threading.Event()
            running.set()
            blocks, failures = [], []
            def audio_worker():
                left, right = (c.c_float * 256)(), (c.c_float * 256)()
                ready.set()
                while running.is_set():
                    if not dll.c3d_process(host, None, None, left, right, 256):
                        failures.append('Concurrent audio callback failed')
                        break
                    blocks.append(sum(v*v for v in left))
            worker = threading.Thread(target=audio_worker, daemon=True)
            worker.start()
            assert ready.wait(2)
            try:
                for _ in range(64):
                    assert dll.c3d_messages_json(host, b''), dll.c3d_error(host)
                    width, height = c.c_uint32(), c.c_uint32()
                    assert dll.c3d_panel_rgba(host, b'1', c.byref(width), c.byref(height)), dll.c3d_error(host)
            finally:
                running.clear()
                worker.join(timeout=5)
            assert not worker.is_alive() and not failures, failures
            assert len(blocks) > 100 and min(blocks) > .001, ('UI interrupted audio', len(blocks), min(blocks, default=0))
            assert dll.c3d_save(host, str(saved).encode()), dll.c3d_error(host)
            assert saved.is_file() and saved.stat().st_size > 0
            assert dll.c3d_load(host, str(saved).encode()), dll.c3d_error(host)
            after = json.loads(dll.c3d_patch_json(host))
            assert before['modules'] == after['modules']
            assert before['cables'] == after['cables']
            print(json.dumps(dict(result='PASS', pid=os.getpid(), modules=2, cables=1,
                                  audio_rms=rms, audio_peak=peak, offline_seconds=2,
                                  processing_seconds=elapsed, patch_roundtrip=True,
                                  direct_catalog_models=190, direct_actions_undo=True,
                                  concurrent_ui_audio_blocks=len(blocks), silent_blocks=0)))
    finally:
        dll.c3d_destroy(host)
    # A fresh lifetime must work after teardown, without stale context or registry.
    host = dll.c3d_create(resources, user_path, 44100, 128)
    assert host, dll.c3d_error(None)
    dll.c3d_destroy(host)
    user.cleanup()

if __name__ == '__main__':
    main()
