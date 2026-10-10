#!/usr/bin/env python3
"""Render the native patch through Cardinal's real plugin in both build variants."""
from pathlib import Path
import hashlib
import json
import subprocess
import shutil
import argparse

ROOT = Path(__file__).resolve().parents[1]

def render(pointer, name, patch):
    build = Path((ROOT / 'build' / pointer).read_text().strip())
    target = build / 'src/CardinalNative'
    shutil.copy2(ROOT / 'tests/audio_render.cpp', target / 'audio_render.cpp')
    (target / 'audio-test.mk').write_text('''include Makefile
audio-test: $(OBJS_DSP) $(OBJS_UI) $(BUILD_DIR)/DistrhoUIMain_JACK.cpp.o $(DGL_LIB)
\t$(CXX) audio_render.cpp $^ $(BUILD_CXX_FLAGS) $(JACK_FLAGS) $(LINK_FLAGS) $(EXTRA_LIBS) $(EXTRA_DSP_LIBS) $(EXTRA_UI_LIBS) $(DGL_LIBS) $(JACK_LIBS) -o audio-test
''')
    args = ['make', '-C', str(target), '-f', 'audio-test.mk', 'audio-test', 'STATIC_BUILD=true', 'PKG_CONFIG=false', 'CARDINAL_3D_PROTOTYPE=true', 'NOPLUGINS=true']
    if name == 'bridge': args.append('CARDINAL_3D_BRIDGE=true')
    subprocess.run(args, check=True)
    output = ROOT / 'build' / (name + '.f32')
    subprocess.run([str(target / 'audio-test'), str(patch), str(output)], check=True)
    return output.read_bytes()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--patch', type=Path, default=ROOT / 'build/integration.vcv')
    parser.add_argument('--report', type=Path, default=ROOT / 'build/audio-comparison.json')
    args = parser.parse_args()
    a = render('cardinal-path.txt', 'bridge', args.patch.resolve())
    b = render('baseline-path.txt', 'baseline', args.patch.resolve())
    assert len(a) == 48000 * 4 * 2 * 4
    assert a == b, 'Audio differs from the bridge-free build'
    report = dict(sample_rate=48000, frames=192000, channels=2, block_size=256, random_seed=[1234567,7654321], byte_identical=True, sha256=hashlib.sha256(a).hexdigest())
    report['patch'] = str(args.patch.resolve())
    args.report.write_text(json.dumps(report, indent=2))
    print('PASS: four seconds of native stereo output are byte-identical to the bridge-free baseline')

if __name__ == '__main__': main()
