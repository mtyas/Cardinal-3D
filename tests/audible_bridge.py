#!/usr/bin/env python3
"""Verify the real Audible Instruments registry, read-only previews and demo patch."""
import json
import argparse
import os
from pathlib import Path
import secrets
import socket
import subprocess
import time
from live_bridge import Client

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--previews-only", action="store_true", help="Validate remaining artwork and wired-rack checks after factory/insertion validation")
    args = parser.parse_args()
    build = Path((ROOT / "build/cardinal-path.txt").read_text().strip())
    with socket.socket() as reservation:
        reservation.bind(("127.0.0.1", 0)); port = reservation.getsockname()[1]
    token = secrets.token_hex(24)
    env = os.environ.copy()
    env.update(CARDINAL_3D_PORT=str(port), CARDINAL_3D_TOKEN=token)
    with (ROOT / "build/audible-runtime.log").open("w") as log:
        process = subprocess.Popen([str(build / "bin/CardinalNative.app/Contents/MacOS/CardinalNative")], env=env, stdout=log, stderr=subprocess.STDOUT)
        client = None
        try:
            for _ in range(100):
                try:
                    client = Client(port, token); break
                except (OSError, ConnectionError): time.sleep(0.2)
            assert client
            client.wait(lambda s: True)
            blank = ROOT / "build/audible-blank.vcv"
            blank.write_text(json.dumps(dict(version="2.4.1", modules=[], cables=[])))
            client.cmd("load", path=str(blank)); client.wait(lambda s: not s["modules"])
            if not args.previews_only:
                models = [m for m in client.catalog if m["plugin"] == "AudibleInstruments"]
                assert len(models) == 20, models
                report = ROOT / "build/audible-library.json"
                client.cmd("describe_library", path=str(report))
                descriptions = json.loads(report.read_text())["modules"]
                assert len(descriptions) == 190 and not any("error" in m for m in descriptions)
                print("PASS: all 20 Audible Instruments factories and runtime descriptors", flush=True)
                fundamental = [m for m in client.catalog if m["plugin"] == "Fundamental"]
                assert len(fundamental) == 26
                for model in fundamental:
                    client.cmd("add", plugin=model["plugin"], model=model["model"])
                    state = client.wait(lambda s: len(s["modules"]) == 1)
                    assert state["modules"][0]["model"] == model["model"]
                    client.cmd("undo")
                    client.wait(lambda s: not s["modules"])
                print("PASS: all 26 Fundamental modules insert and undo through the native runtime", flush=True)
                befaco = [m for m in client.catalog if m["plugin"] == "Befaco"]
                assert len(befaco) == 31
                assert all(m.get("module_name") and m.get("manufacturer") and m.get("tags") for m in client.catalog)
                for model in befaco:
                    client.cmd("add", plugin=model["plugin"], model=model["model"])
                    state = client.wait(lambda s: len(s["modules"]) == 1)
                    assert state["modules"][0]["model"] == model["model"]
                    client.cmd("undo"); client.wait(lambda s: not s["modules"])
                print("PASS: all 31 Befaco modules insert/undo; manufacturer and type metadata available", flush=True)
                bogaudio = [m for m in client.catalog if m["plugin"] == "Bogaudio"]
                assert len(bogaudio) == 111
                for index, model in enumerate(bogaudio):
                    if index % 10 == 0: print(f"CHECK: Bogaudio {index + 1}/{len(bogaudio)} · {model['model']}", flush=True)
                    client.cmd("add", plugin=model["plugin"], model=model["model"])
                    state = client.wait(lambda s: len(s["modules"]) == 1)
                    assert state["modules"][0]["model"] == model["model"]
                    client.cmd("undo"); client.wait(lambda s: not s["modules"])
                print("PASS: all 111 Bogaudio modules insert and undo", flush=True)
            # Browser previews must not insert modules or cables into the playing patch.
            for page in range(0, len(client.catalog), 16):
                print(f"CHECK: previews {page + 1}–{min(page + 16, len(client.catalog))}/{len(client.catalog)}", flush=True)
                client.cmd("preview_clear")
                ids = []
                for model in client.catalog[page:page+16]:
                    ids.append("preview/" + model["plugin"] + "/" + model["model"])
                    client.cmd("preview", plugin=model["plugin"], model=model["model"])
                deadline = time.monotonic() + 20
                while not all(id in client.previews and id in client.surfaces for id in ids) and time.monotonic() < deadline:
                    client.next(); client.send(dict(op="heartbeat", request=0))
                assert all(id in client.previews and id in client.surfaces for id in ids), ids
                assert not client.snapshot["modules"] and not client.snapshot["cables"]
            client.cmd("preview_clear")
            print("PASS: native artwork previews for all 190 models without patch/audio-engine insertion", flush=True)
            old_generation = client.snapshot["generation"]
            client.cmd("add", plugin="AudibleInstruments", model="Plaits")
            client.wait(lambda s: len(s["modules"]) == 1)
            client.request += 1
            request = client.request
            client.send(dict(op="preview_clear", generation=old_generation, request=request))
            while True:
                reply = client.next()
                if reply.get("type") == "ack" and reply.get("request") == request:
                    assert reply["ok"], reply
                    break
            client.cmd("undo"); client.wait(lambda s: not s["modules"])
            print("PASS: browser preview cleanup remains valid after insertion changes generation", flush=True)
            client.cmd("audible_starter")
            state = client.wait(lambda s: len(s["modules"]) == 5 and len(s["cables"]) == 5)
            assert {m["model"] for m in state["modules"]} == {"Plaits", "Ripples", "VCA-1", "Scope", "HostAudio2"}
            patch = ROOT / "build/audible-demo.vcv"
            client.cmd("save", path=str(patch))
            client.cmd("load", path=str(patch))
            client.wait(lambda s: len(s["modules"]) == 5 and len(s["cables"]) == 5)
            plaits = next(m for m in client.snapshot["modules"] if m["model"] == "Plaits")
            knobs = [c for c in plaits["controls"] if c["kind"] == "knob"]
            assert len(knobs) == 9 and sum(c["visible"] for c in knobs) == 7
            hidden = [c for c in knobs if not c["visible"]]
            assert len(hidden) == 2 and all(any(v["visible"] and v["x"] == c["x"] and v["y"] == c["y"] for v in knobs) for c in hidden)
            print("PASS: Plaits alternate LPG knobs are hidden while Timbre/Morph are visible", flush=True)
            knob = next(c for c in plaits["controls"] if c.get("label") == "Harmonics")
            before = knob["value"]
            client.pointer(plaits, knob, "down")
            client.cmd("drag_delta", dx=0, dy=-20, mods=0)
            client.pointer(plaits, knob, "up", dy=-20)
            def harmonics(s):
                m = next(m for m in s["modules"] if m["model"] == "Plaits")
                return next(c["value"] for c in m["controls"] if c.get("label") == "Harmonics")
            client.wait(lambda s: harmonics(s) != before)
            client.cmd("undo")
            try:
                client.wait(lambda s: abs(harmonics(s)-before) < 1e-5)
            except AssertionError:
                print(f"Parameter undo values: before={before}, after={harmonics(client.snapshot)}", flush=True)
                raise
            print("PASS: wired Plaits/Ripples rack, native save/load and parameter undo", flush=True)
        finally:
            if client: client.peer.close()
            process.terminate(); process.wait(timeout=10)

if __name__ == "__main__": main()
