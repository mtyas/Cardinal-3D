#!/usr/bin/env python3
"""Integration checks against the real Cardinal standalone runtime."""
import hashlib
import argparse
import json
import os
from pathlib import Path
import secrets
import socket
import struct
import subprocess
import time
import zlib

ROOT = Path(__file__).resolve().parents[1]

class Client:
    def __init__(self, port, token):
        self.peer = socket.create_connection(("127.0.0.1", port), timeout=15)
        self.snapshot = None
        self.surfaces = {}
        self.scene_surface = None
        self.previews = {}
        self.catalog = []
        self.request = 0
        self.last_heartbeat = 0.0
        self.cmd("hello", version=1, token=token)

    def send(self, command):
        if command.get("op") == "heartbeat":
            now = time.monotonic()
            if now - self.last_heartbeat < 0.25:
                return
            self.last_heartbeat = now
        data = b"\x01" + json.dumps(command).encode()
        self.peer.sendall(struct.pack("<I", len(data)) + data)

    def next(self):
        def read(count):
            data = bytearray()
            while len(data) < count:
                chunk = self.peer.recv(count - len(data))
                if not chunk:
                    raise ConnectionError("Disconnected")
                data.extend(chunk)
            return bytes(data)
        size = struct.unpack("<I", read(4))[0]
        assert 1 <= size <= 24 * 1024 * 1024
        frame = read(size)
        if frame[0] == 1:
            value = json.loads(frame[1:])
            if value.get("type") == "snapshot":
                self.snapshot = value
            elif value.get("type") == "preview":
                self.previews[value["descriptor"]["id"]] = value["descriptor"]
            elif value.get("type") == "catalog":
                self.catalog = value["models"]
            return value
        assert frame[0] == 2
        header_size = struct.unpack("<I", frame[1:5])[0]
        header = json.loads(frame[5:5+header_size])
        pixels = frame[5+header_size:]
        assert len(pixels) == header["width"] * header["height"] * 4
        self.surfaces.setdefault(header["module"], set()).add(hashlib.sha256(pixels).hexdigest())
        if header["module"] == "scene":
            self.scene_surface = (header, pixels)
        return header

    def cmd(self, op, **data):
        self.request += 1
        self.send(dict(op=op, request=self.request, generation=self.snapshot["generation"] if self.snapshot else "", **data))
        deadline = time.monotonic()+(180 if op == "describe_library" else 20)
        while time.monotonic() < deadline:
            value = self.next()
            self.send(dict(op="heartbeat", request=0))
            if value.get("type") == "ack" and value.get("request") == self.request:
                assert value["ok"], value
                return value
        raise TimeoutError(op)

    def wait(self, predicate, seconds=15):
        deadline = time.monotonic()+seconds
        while time.monotonic() < deadline:
            if self.snapshot and predicate(self.snapshot):
                return self.snapshot
            self.next()
            self.send(dict(op="heartbeat", request=0))
        raise AssertionError("Snapshot condition failed")

    def pointer(self, module, control, phase, dy=0, mods=0):
        self.cmd("pointer", module=module["id"], x=control["x"], y=control["y"]+dy, phase=phase, button=0, mods=mods)

def verify_vr_actions(client, vco, scope):
    # VR patching bypasses pixel hit testing and preserves a single undo step.
    client.cmd("patch_cable", output_module=vco["id"], output_port=0, input_module=scope["id"], input_port=1)
    state = client.wait(lambda s: len(s["cables"]) == 6)
    added_cable = next(c for c in state["cables"] if c["input_module"] == scope["id"] and c["input_port"] == 1)
    client.cmd("patch_cable", output_module=vco["id"], output_port=0, input_module=scope["id"], input_port=1)
    client.wait(lambda s: len(s["cables"]) == 6)
    client.cmd("patch_cable", output_module=vco["id"], output_port=0, input_module=scope["id"], input_port=0, replace_cable=added_cable["id"])
    client.wait(lambda s: len(s["cables"]) == 5)
    client.cmd("undo")
    client.wait(lambda s: len(s["cables"]) == 6)
    client.cmd("undo")
    client.wait(lambda s: len(s["cables"]) == 5)
    print("PASS: direct socket patching, occupied-input replacement and single-step undo", flush=True)
    client.cmd("patch_cable", output_module=vco["id"], output_port=0, input_module=scope["id"], input_port=1)
    state = client.wait(lambda s: len(s['cables']) == 6)
    unplug = next(c for c in state['cables'] if c['input_module'] == scope['id'] and c['input_port'] == 1)
    client.cmd("disconnect_cable", cable_id=unplug['id'], input_module=scope['id'], input_port=1)
    client.wait(lambda s: len(s['cables']) == 5)
    client.cmd('undo')
    client.wait(lambda s: len(s['cables']) == 6)
    client.cmd('undo')
    client.wait(lambda s: len(s['cables']) == 5)
    print('PASS: unplugging a specific cable and restoring it with undo', flush=True)
    positions = {m["id"]: (m["x"], m["y"]) for m in client.snapshot["modules"]}
    client.cmd("move_begin", module=scope["id"])
    client.cmd("move_delta", dx=vco["x"]-scope["x"], dy=0, insert=True)
    client.cmd("move_end")
    state = client.wait(lambda s: next(m for m in s["modules"] if m["id"] == scope["id"])["x"] == vco["x"])
    row = sorted(state["modules"], key=lambda m: m["x"])
    assert all(a["x"] + a["width"] <= b["x"] for a, b in zip(row, row[1:])), "Insertion overlapped modules"
    client.cmd("undo")
    client.wait(lambda s: {m["id"]: (m["x"], m["y"]) for m in s["modules"]} == positions)
    print("PASS: module insertion shifts neighbors and undoes the whole layout", flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--full", action="store_true")
    args = parser.parse_args()
    build = Path((ROOT / "build" / ("full-path.txt" if args.full else "cardinal-path.txt")).read_text().strip())
    executable = build / "bin/CardinalNative.app/Contents/MacOS/CardinalNative"
    token = secrets.token_hex(24)
    with socket.socket() as reservation:
        reservation.bind(("127.0.0.1", 0)); port = reservation.getsockname()[1]
    env = os.environ.copy()
    env.update(CARDINAL_3D_PORT=str(port), CARDINAL_3D_TOKEN=token, CARDINAL_3D_OVERRIDES=str(ROOT / "bridge/overrides.json"))
    log = open(ROOT / "build/live-cardinal.log", "w")
    process = subprocess.Popen([str(executable)], env=env, stdout=log, stderr=subprocess.STDOUT)
    client = None
    try:
        deadline = time.monotonic()+30
        while time.monotonic() < deadline:
            if process.poll() is not None:
                raise RuntimeError(f"Cardinal exited: {process.returncode}; see build/live-cardinal.log")
            try:
                client = Client(port, token); break
            except (OSError, ConnectionError):
                time.sleep(0.2)
        assert client is not None, "Bridge did not start"
        client.wait(lambda s: True)
        blank = ROOT / "build/blank.vcv"
        blank.write_text(json.dumps(dict(version="2.4.1", modules=[], cables=[])))
        client.cmd("load", path=str(blank))
        client.wait(lambda s: len(s["modules"]) == 0)
        client.cmd("starter")
        state = client.wait(lambda s: len(s["modules"]) == 6 and len(s["cables"]) == 5)
        assert len({m["id"] for m in state["modules"]}) == 6
        for model in ["ADSR", "Scope", "VCA-1"]:
            descriptor = next(m for m in state["modules"] if m["model"] == model)
            assert len(descriptor["screens"]) == 1, descriptor
            region = descriptor["screens"][0]
            assert region["width"] > 0 and region["height"] > 0
        print("PASS: six real modules and five cables", flush=True)
        vco = next(m for m in state["modules"] if m["model"] == "VCO")
        scope = next(m for m in state["modules"] if m["model"] == "Scope")
        knob = next(c for c in vco["controls"] if c["kind"] == "knob" and c["id"] == 2)
        old = knob["value"]
        verify_vr_actions(client, vco, scope)
        def frequency(s):
            m = next(m for m in s["modules"] if m["id"] == vco["id"])
            return next(c["value"] for c in m["controls"] if c["kind"] == "knob" and c["id"] == 2)
        for phase, dy in [("down", 0), ("motion", -30), ("up", -30)]:
            client.pointer(vco, knob, phase, dy)
        moved = frequency(client.wait(lambda s: frequency(s) != old))
        client.cmd("undo")
        client.wait(lambda s: abs(frequency(s)-old) < 1e-5)
        client.cmd("redo"); client.wait(lambda s: abs(frequency(s)-moved) < 1e-5)
        print("PASS: parameter gesture and undo/redo", flush=True)
        time.sleep(0.35) # Cardinal's double-click reset window is 300 ms.
        client.pointer(vco, knob, "down", mods=8)
        client.pointer(vco, knob, "motion", -30, mods=8)
        client.pointer(vco, knob, "up", -30, mods=8)
        fine = frequency(client.wait(lambda s: frequency(s) != moved))
        assert abs(fine-moved) < abs(moved-old) * 0.2
        client.cmd("undo"); client.wait(lambda s: abs(frequency(s)-moved) < 1e-5)
        client.pointer(vco, knob, "motion"); client.cmd("reset_hovered")
        client.wait(lambda s: abs(frequency(s)-knob["default"]) < 1e-5)
        client.cmd("undo"); client.wait(lambda s: abs(frequency(s)-moved) < 1e-5)
        time.sleep(0.35)
        client.pointer(vco, knob, "down")
        client.cmd("drag_delta", dx=0, dy=-10000, mods=0)
        client.pointer(vco, knob, "up", -10000)
        client.wait(lambda s: abs(frequency(s)-knob["max"]) < 1e-5)
        client.cmd("undo"); client.wait(lambda s: abs(frequency(s)-moved) < 1e-5)
        client.cmd("pointer", module=vco["id"], x=knob["x"], y=knob["y"], phase="down", button=1, mods=0)
        client.wait(lambda s: s["overlay"])
        assert client.snapshot["overlay_mode"] == "menu"
        deadline = time.monotonic() + 10
        while not client.scene_surface and time.monotonic() < deadline:
            client.next(); client.send(dict(op="heartbeat", request=0))
        assert client.scene_surface, "Missing native menu surface"
        header, pixels = client.scene_surface
        assert header["overlay_mode"] == "menu", header
        assert header["width"] < 1000 and header["height"] < 900, header
        assert "origin_x" in header and "origin_y" in header
        assert 0 in pixels[3::4], "Menu crop must preserve transparent surroundings"
        def chunk(kind, data):
            return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
        width, height = header["width"], header["height"]
        rows = b"".join(b"\0" + pixels[y*width*4:(y+1)*width*4] for y in range(height))
        png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b"")
        (ROOT / "build/menu-crop.png").write_bytes(png)
        client.cmd("escape"); client.wait(lambda s: not s["overlay"])
        client.scene_surface = None
        client.cmd("pointer", module=vco["id"], x=knob["x"], y=knob["y"], phase="down", button=1, mods=0)
        client.wait(lambda s: s["overlay_mode"] == "menu")
        while not client.scene_surface:
            client.next(); client.send(dict(op="heartbeat", request=0))
        assert client.scene_surface[0]["overlay_mode"] == "menu"
        client.cmd("escape"); client.wait(lambda s: not s["overlay"])
        client.scene_surface = None
        client.cmd("overlay", enabled=True)
        client.wait(lambda s: s["overlay_mode"] == "full")
        while not client.scene_surface:
            client.next(); client.send(dict(op="heartbeat", request=0))
        assert client.scene_surface[0]["overlay_mode"] == "full"
        client.cmd("escape"); client.wait(lambda s: not s["overlay"])
        print("PASS: fine adjustment, reset, limits and native parameter menu", flush=True)
        output = next(c for c in vco["controls"] if c["kind"] == "port" and c["direction"] == "output" and c["id"] == 1)
        input_port = next(c for c in scope["controls"] if c["kind"] == "port" and c["direction"] == "input" and c["id"] == 1)
        client.pointer(vco, output, "down")
        client.wait(lambda s: bool(s.get("pending_cable")))
        client.pointer(scope, input_port, "motion")
        client.pointer(scope, input_port, "up")
        client.wait(lambda s: len(s["cables"]) == 6)
        client.cmd("disconnect_port", module=scope["id"], direction="input", port=1)
        client.wait(lambda s: len(s["cables"]) == 5)
        client.cmd("undo"); client.wait(lambda s: len(s["cables"]) == 6)
        print("PASS: cable gesture, removal and undo", flush=True)
        # Move an existing connection to a different output using the original PortWidget action.
        client.pointer(vco, output, "down")
        square = next(c for c in vco["controls"] if c["kind"] == "port" and c["direction"] == "output" and c["id"] == 3)
        client.pointer(vco, square, "motion"); client.pointer(vco, square, "up")
        client.wait(lambda s: any(c["output_port"] == 3 and c["input_module"] == scope["id"] for c in s["cables"]))
        print("PASS: cable movement and acknowledged floating cable", flush=True)
        adsr = next(m for m in state["modules"] if m["model"] == "ADSR")
        trigger = next(c for c in adsr["controls"] if c.get("momentary"))
        def param(s, module_id, param_id):
            return next(c["value"] for m in s["modules"] if m["id"] == module_id for c in m["controls"] if c["id"] == param_id and "value" in c)
        client.pointer(adsr, trigger, "down")
        client.wait(lambda s: param(s, adsr["id"], trigger["id"]) == 1)
        client.cmd("release")
        client.wait(lambda s: param(s, adsr["id"], trigger["id"]) == 0 and not s["gesture_active"])
        mode = next(c for c in scope["controls"] if c.get("label") == "Scope mode")
        client.pointer(scope, mode, "down"); client.pointer(scope, mode, "up")
        client.wait(lambda s: param(s, scope["id"], mode["id"]) != mode["value"])
        client.cmd("undo"); client.wait(lambda s: param(s, scope["id"], mode["id"]) == mode["value"])
        print("PASS: momentary release, Scope switch and native undo", flush=True)
        client.wait(lambda s: len(client.surfaces.get(scope["id"], set())) >= 2)
        print("PASS: changing live scope texture", flush=True)
        patch = ROOT / "build/integration.vcv"
        client.cmd("save", path=str(patch))
        assert patch.exists() and patch.stat().st_size > 100
        previous_generation = client.snapshot["generation"]
        client.pointer(vco, knob, "down")
        client.cmd("load", path=str(patch))
        client.wait(lambda s: len(s["modules"]) == 6 and len(s["cables"]) == 6 and not s["gesture_active"])
        assert client.snapshot["generation"] != previous_generation
        client.request += 1
        client.send(dict(op="remove", module=vco["id"], generation=previous_generation, request=client.request))
        while True:
            answer = client.next()
            if answer.get("type") == "ack" and answer.get("request") == client.request:
                assert not answer["ok"] and "Stale scene" in answer["error"]
                break
        print("PASS: native patch save/load", flush=True)
        print("PASS: patch reload during a gesture and rejection of stale commands", flush=True)
        if args.full:
            client.cmd("add", plugin="Fundamental", model="Merge")
            merged_state = client.wait(lambda s: len(s["modules"]) == 7)
            merge = next(m for m in merged_state["modules"] if m["model"] == "Merge")
            def find_port(m, direction, index):
                return next(c for c in m["controls"] if c["kind"] == "port" and c["direction"] == direction and c["id"] == index)
            for index in range(4):
                client.pointer(vco, find_port(vco, "output", index), "down", mods=8)
                client.pointer(merge, find_port(merge, "input", index), "motion")
                client.pointer(merge, find_port(merge, "input", index), "up")
            client.pointer(merge, find_port(merge, "output", 0), "down")
            client.pointer(adsr, find_port(adsr, "input", 0), "motion")
            client.pointer(adsr, find_port(adsr, "input", 0), "up")
            client.wait(lambda s: find_port(next(m for m in s["modules"] if m["id"] == adsr["id"]), "input", 0)["channels"] == 4)
            print("PASS: four-channel polyphonic connection through native ports", flush=True)
            client.cmd("remove", module=merge["id"])
            client.wait(lambda s: len(s["modules"]) == 6)
        report = ROOT / "build" / ("full-library.json" if args.full else "library.json")
        client.cmd("describe_library", path=str(report))
        coverage = json.loads(report.read_text())["modules"]
        assert len(coverage) >= 7
        assert all("descriptor" in m for m in coverage), [m for m in coverage if "error" in m]
        print(f"PASS: runtime descriptors for all {len(coverage)} loaded models", flush=True)
        vco = next(m for m in client.snapshot["modules"] if m["model"] == "VCO")
        client.pointer(vco, knob, "down")
        client.cmd("remove", module=vco["id"])
        client.wait(lambda s: len(s["modules"]) == 5)
        client.cmd("undo"); client.wait(lambda s: len(s["modules"]) == 6)
        print("PASS: removal during gesture and undo", flush=True)
        client.peer.close()
        time.sleep(0.2)
        client = Client(port, token)
        client.wait(lambda s: len(s["modules"]) == 6)
        print("PASS: disconnect/reconnect", flush=True)
        client.pointer(adsr, trigger, "down")
        client.wait(lambda s: param(s, adsr["id"], trigger["id"]) == 1)
        client.peer.close(); time.sleep(0.3)
        client = Client(port, token)
        client.wait(lambda s: not s["gesture_active"] and param(s, adsr["id"], trigger["id"]) == 0)
        print("PASS: disconnect releases held momentary control", flush=True)
        vco = next(m for m in client.snapshot["modules"] if m["model"] == "VCO")
        knob = next(c for c in vco["controls"] if c["kind"] == "knob" and c["id"] == 2)
        old = knob["value"]
        client.pointer(vco, knob, "down"); client.cmd("release")
        client.wait(lambda s: not s["gesture_active"])
        assert abs(frequency(client.snapshot)-old) < 1e-5, "Release changed the parameter"
        print("PASS: gesture cancellation preserves the parameter value", flush=True)
        adsr = next(m for m in client.snapshot["modules"] if m["model"] == "ADSR")
        client.pointer(adsr, trigger, "down")
        client.wait(lambda s: param(s, adsr["id"], trigger["id"]) == 1)
        time.sleep(3.6) # Simulate a stalled frontend with no heartbeat or reads.
        client.peer.close()
        client = Client(port, token)
        client.wait(lambda s: not s["gesture_active"] and param(s, adsr["id"], trigger["id"]) == 0)
        print("PASS: heartbeat timeout releases a stalled frontend's controls", flush=True)
    finally:
        if client:
            client.peer.close()
        process.terminate()
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill(); process.wait()
        log.close()

if __name__ == "__main__":
    main()
