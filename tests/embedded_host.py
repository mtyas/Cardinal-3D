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
    parser.add_argument('--minimum-models', type=int, default=190)
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
    dll.c3d_push_midi.argtypes = [c.c_void_p, c.POINTER(c.c_uint8), c.c_uint32]
    dll.c3d_midi_panic.argtypes = [c.c_void_p]
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
            assert len(catalog['models']) >= args.minimum_models
            assert len(state['modules']) == 2 and len(state['cables']) == 1
            vco = next(m for m in state['modules'] if m['model'] == 'VCO')
            assert any(p.get('body_color') for p in vco['controls'] if p['kind'] == 'knob')
            cable = state['cables'][0]
            invalid_delete = dict(op='remove_many', request=90, generation=state['generation'], modules=['1', 'missing'])
            invalid_messages = json.loads(dll.c3d_messages_json(host, json.dumps(invalid_delete).encode()))
            assert not next(m for m in invalid_messages if m['type'] == 'ack')['ok']
            assert len(json.loads(dll.c3d_patch_json(host))['modules']) == 2, 'Invalid rack deletion must be atomic'
            command('remove_many', modules=['1', '2'])
            assert not state['modules'] and not state['cables'], 'Rack deletion must remove its modules and attached cables'
            command('undo')
            assert len(state['modules']) == 2 and len(state['cables']) == 1, 'One undo must restore the whole deleted rack contents'
            command('disconnect_cable', cable_id=cable['id'], input_module=cable['input_module'], input_port=cable['input_port'])
            assert not state['cables']
            command('undo')
            assert len(state['cables']) == 1
            command('add', plugin='Fundamental', model='VCA-1')
            assert len(state['modules']) == 3
            command('undo')
            assert len(state['modules']) == 2
            # Each queued action must keep its own acknowledgment/history while
            # producing just one final live snapshot. Invalid batches are atomic.
            batch = [dict(op='disconnect_cable', request=20, generation=state['generation'],
                          cable_id=cable['id'], input_module=cable['input_module'], input_port=cable['input_port']),
                     dict(op='undo', request=21, generation=state['generation'])]
            assert not dll.c3d_messages_json(host, json.dumps([batch[0], None]).encode())
            assert before == json.loads(dll.c3d_patch_json(host)), 'Malformed batch must not execute its first action'
            response = dll.c3d_messages_json(host, json.dumps(batch).encode())
            assert response, dll.c3d_error(host)
            messages = json.loads(response)
            acks = [m for m in messages if m['type'] == 'ack']
            assert [m['request'] for m in acks] == [20, 21] and all(m['ok'] for m in acks), acks
            assert len([m for m in messages if m['type'] == 'snapshot']) == 1
            assert len(next(m for m in messages if m['type'] == 'snapshot')['cables']) == 1
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
            mixer_faders_verified = False
            if any(model['plugin'] == 'MindMeldModular' and model['model'] == 'MixMaster' for model in catalog['models']):
                mixer_path = Path(scratch) / 'mixer.vcv'
                mixer_path.write_text(json.dumps(dict(version='2.4.1', modules=[
                    dict(id=1, plugin='MindMeldModular', model='MixMaster', pos=[0, 0], params=[])], cables=[])), encoding='utf-8')
                assert dll.c3d_load(host, str(mixer_path).encode()), dll.c3d_error(host)
                state = {}
                command('hello', version=1)
                sliders = [control for control in state['modules'][0]['controls'] if control['kind'] == 'slider']
                assert len(sliders) >= 16, 'MixMaster faders must retain native slider semantics'
                arrows = [control for control in state['modules'][0]['controls'] if 'MmGroupPlusButton' in control.get('component_type', '')]
                assert len(arrows) >= 16, 'MixMaster non-parameter bus arrows must be exposed as interactive native surfaces'
                groups = [control for control in state['modules'][0]['controls'] if control.get('component_type') == 'GroupSelectDisplay']
                assert groups, 'MixMaster bus selection values must be visible in metadata'
                group = min(groups, key=lambda control: abs(control['x'] - arrows[0]['x']) + abs(control['y'] - arrows[0]['y']))
                initial_group = group['value']
                arrow = arrows[0]
                command('pointer', module='1', x=arrow['x'], y=arrow['y'], phase='down', button=0, mods=0)
                command('hello', version=1)
                command('pointer', module='1', x=arrow['x'], y=arrow['y'], phase='up', button=0, mods=0)
                changed_group = next(control for control in state['modules'][0]['controls'] if control['id'] == group['id'] and control.get('component_type') == 'GroupSelectDisplay')
                assert changed_group['value'] != initial_group, 'A native bus arrow click must change its linked channel routing parameter'
                command('parameter_choices', module='1', param=group['id'], x=group['x'], y=group['y'])
                assert state['overlay_mode'] == 'menu', 'Clicking the bus display must open native routing choices'
                command('escape')
                module_position = (state['modules'][0]['x'], state['modules'][0]['y'])
                command('pointer', module='1', x=1, y=140, phase='down', button=0, mods=0)
                command('drag_delta', dx=70, dy=35, mods=0)
                command('release')
                assert (state['modules'][0]['x'], state['modules'][0]['y']) == module_position, 'Decorative surface clicks must never move modules outside title-strip placement'
                for slider in sliders[:2]:
                    initial = slider['normalized']
                    assert abs(slider['y'] - (slider['start_y'] + initial * (slider['end_y'] - slider['start_y']))) < .1, 'Aiming must follow the live fader handle'
                    command('pointer', module='1', x=slider['x'], y=slider['y'], phase='down', button=0, mods=0)
                    command('drag_delta', dx=0, dy=30, mods=0)
                    command('release')
                    changed = next(control for control in state['modules'][0]['controls'] if control['kind'] == 'slider' and control['id'] == slider['id'])
                    assert abs(changed['normalized'] - initial) > .01, 'Captured MixMaster fader must respond to vertical dragging'
                    command('undo')
                    restored = next(control for control in state['modules'][0]['controls'] if control['kind'] == 'slider' and control['id'] == slider['id'])
                    assert abs(restored['normalized'] - initial) < .001, 'Fader changes must retain native undo'
                mixer_faders_verified = True
            midi_verified = False
            if any(model['plugin'] == 'Cardinal' and model['model'] == 'HostMIDI' for model in catalog['models']):
                midi_path = Path(scratch) / 'midi.vcv'
                midi_path.write_text(json.dumps(dict(version='2.4.1', modules=[
                    dict(id=1, plugin='Cardinal', model='HostMIDI', pos=[0, 0], params=[]),
                    # Gate is DC, so bypass the audio module's normal DC blocker.
                    dict(id=2, plugin='Cardinal', model='HostAudio2', pos=[10, 0], params=[], data=dict(dcFilter=False))],
                    cables=[dict(id=3, outputModuleId=1, outputId=1, inputModuleId=2, inputId=0, color='#ff5252')])), encoding='utf-8')
                assert dll.c3d_load(host, str(midi_path).encode()), dll.c3d_error(host)
                def midi(*message):
                    return dll.c3d_push_midi(host, (c.c_uint8 * len(message))(*message), len(message))
                assert not midi(0x90, 60), 'Truncated channel message must be rejected'
                assert midi(0x90, 60, 100)
                for _ in range(2): assert dll.c3d_process(host, None, None, out_l, out_r, 256)
                assert sum(abs(v) for v in out_l) / 256 > .2, 'MIDI note must reach native MIDI-to-CV gate'
                assert midi(0x80, 60, 0)
                for _ in range(2): assert dll.c3d_process(host, None, None, out_l, out_r, 256)
                assert max(abs(v) for v in out_l) < .0001, 'MIDI note off must release gate'
                assert midi(0x90, 60, 100)
                assert dll.c3d_process(host, None, None, out_l, out_r, 256)
                assert dll.c3d_midi_panic(host)
                for _ in range(2): assert dll.c3d_process(host, None, None, out_l, out_r, 256)
                assert max(abs(v) for v in out_l) < .0001, 'Panic must release held notes'
                midi_verified = True
            print(json.dumps(dict(result='PASS', pid=os.getpid(), modules=2, cables=1,
                                  audio_rms=rms, audio_peak=peak, offline_seconds=2,
                                  processing_seconds=elapsed, patch_roundtrip=True,
                                  direct_catalog_models=len(catalog['models']), direct_actions_undo=True,
                                  concurrent_ui_audio_blocks=len(blocks), silent_blocks=0, midi_gate_and_panic=midi_verified,
                                  mixmaster_faders=mixer_faders_verified)))
    finally:
        dll.c3d_destroy(host)
    # A fresh lifetime must work after teardown, without stale context or registry.
    host = dll.c3d_create(resources, user_path, 44100, 128)
    assert host, dll.c3d_error(None)
    dll.c3d_destroy(host)
    user.cleanup()

if __name__ == '__main__':
    main()
