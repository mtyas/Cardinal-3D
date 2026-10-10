extends SceneTree

var bridge
var started := 0
var requested := false
var snapshots := 0
var surfaces := 0
var compressed := 0
var largest_backlog := 0

func _initialize() -> void: call_deferred("run")

func run() -> void:
	Engine.max_fps = 72
	bridge = load("res://scripts/bridge_client.gd").new()
	root.add_child(bridge)
	bridge.message_received.connect(func(message: Dictionary):
		if message.get("type") != "snapshot": return
		if not requested:
			requested = true
			bridge.send_command("load", {"path": OS.get_environment("CARDINAL_3D_PROBE_PATCH")})
		elif not message.get("modules", []).is_empty():
			if started == 0: started = Time.get_ticks_msec()
			snapshots += 1)
	bridge.surface_received.connect(func(header: Dictionary, _image: Image):
		surfaces += 1
		if header.get("encoding") == "zstd": compressed += 1)
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		largest_backlog = maxi(largest_backlog, bridge.incoming.size())
		if started > 0 and Time.get_ticks_msec() - started >= 8000:
			var elapsed := float(Time.get_ticks_msec() - started) / 1000
			print("Live artwork stream: " + JSON.stringify({"snapshot_hz": snapshots / elapsed, "surfaces": surfaces, "compressed_surfaces": compressed, "largest_backlog_bytes": largest_backlog}))
			bridge._drop()
			quit(0 if snapshots / elapsed > 15 and compressed > 0 else 1)
			return
	push_error("Live artwork stream timed out")
	quit(1)
