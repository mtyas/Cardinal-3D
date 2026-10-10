#!/usr/bin/env python3
"""Request real runtime descriptors from the bridge and summarize fallback coverage."""
import argparse
import json
import os
from pathlib import Path
import socket
import struct
import time

def receive(peer):
    def read(count):
        data = bytearray()
        while len(data) < count:
            packet = peer.recv(count - len(data))
            if not packet:
                raise ConnectionError("Cardinal disconnected")
            data.extend(packet)
        return bytes(data)
    length = struct.unpack("<I", read(4))[0]
    if length < 1 or length > 24 * 1024 * 1024:
        raise ValueError("Invalid bridge frame")
    data = read(length)
    return json.loads(data[1:]) if data[0] == 1 else None

def send(peer, **command):
    payload = b"\x01" + json.dumps(command).encode()
    peer.sendall(struct.pack("<I", len(payload)) + payload)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=int(os.getenv("CARDINAL_3D_PORT", "39413")))
    parser.add_argument("--output", type=Path, default=Path("reports/library.json"))
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with socket.create_connection(("127.0.0.1", args.port), timeout=180) as peer:
        send(peer, op="hello", version=1, token=os.getenv("CARDINAL_3D_TOKEN", ""), request=1)
        while True:
            message = receive(peer)
            if message and message.get("type") == "snapshot":
                generation = message["generation"]
                break
        send(peer, op="describe_library", path=str(args.output.resolve()), generation=generation, request=2)
        while True:
            message = receive(peer)
            send(peer, op="heartbeat", request=0)
            if message and message.get("type") == "ack" and message.get("request") == 2:
                if not message["ok"]:
                    raise RuntimeError(message["error"])
                break
    report = json.loads(args.output.read_text())
    for item in report["modules"]:
        controls = item.get("descriptor", {}).get("controls", [])
        item["physical_controls"] = sum(c.get("physical", False) for c in controls)
        item["surface_controls"] = len(controls) - item["physical_controls"]
        item["required_overrides"] = sorted({c.get("component_type", c["kind"]) for c in controls if c["kind"] == "custom"})
        item["fallback_coverage"] = "complete module surface" if "descriptor" in item else "factory failed"
    args.output.write_text(json.dumps(report, indent=2))
    print(f"Inspected {len(report['modules'])} bundled models; report: {args.output.resolve()}")

if __name__ == "__main__":
    main()
