extends "res://scripts/bridge_client.gd"
## Experimental in-process backend. The normal bridge remains the default.
var native
var audio_player: AudioStreamPlayer
var audio_playback
var commands: Array[Dictionary] = []
var panel_requests: Dictionary = {}
var panels: Dictionary = {}
var local_snapshot := {}
var native_surface_count := 0
var recovery_path := ""
var closed := false
var recovery_elapsed := 0.0
var recovery_saved := true

func _ready() -> void:
	_boot.call_deferred()

func _boot() -> void:
	if not ClassDB.class_exists("CardinalEmbeddedHost"):
		push_error("Embedded engine extension is not loaded")
		return
	native = ClassDB.instantiate("CardinalEmbeddedHost")
	var resources := OS.get_environment("CARDINAL_EMBEDDED_RESOURCES")
	var user_path := OS.get_environment("CARDINAL_EMBEDDED_USER_DIR")
	if user_path.is_empty(): user_path = ProjectSettings.globalize_path("user://embedded")
	recovery_path = user_path.path_join("autosave.vcv")
	if not native.initialize(resources, user_path, AudioServer.get_mix_rate(), 256):
		push_error(native.last_error())
		return
	var patch := OS.get_environment("CARDINAL_EMBEDDED_PATCH")
	if patch.is_empty() and FileAccess.file_exists(recovery_path): patch = recovery_path
	if not patch.is_empty() and not native.load_patch(patch):
		push_error(native.last_error())
		native.close()
		return
	connected = true
	connection_changed.emit(true)
	_ingest(native.messages_json(JSON.stringify({"op": "hello", "request": 0, "version": 1})))
	if patch.is_empty():
		_ingest(native.messages_json(JSON.stringify({"op": "starter", "request": 0, "generation": generation})))
	_load_panels(32)
	audio_player = AudioStreamPlayer.new()
	add_child(audio_player)
	audio_player.stream = native.create_audio_stream()
	audio_player.play()
	audio_playback = audio_player.get_stream_playback()

func send_command(operation: String, data: Dictionary = {}) -> int:
	if not connected: return -1
	var command := data.duplicate(true)
	command["op"] = operation
	command["request"] = next_id
	command["generation"] = generation
	next_id += 1
	if commands.size() >= 256: return -1
	commands.append(command)
	return command.request

func _process(delta: float) -> void:
	if not connected: return
	for _index in range(mini(commands.size(), 8)):
		var result: String = native.messages_json(JSON.stringify(commands[0]))
		if result.is_empty(): break # Retry a temporarily unavailable owner operation.
		commands.pop_front()
		_ingest(result)
	var state: String = native.messages_json("")
	if not state.is_empty(): _ingest(state)
	_load_panels(1)
	var header_text: String = native.render_surface()
	if not header_text.is_empty():
		var header: Variant = JSON.parse_string(header_text)
		var image: Image = native.surface_image()
		if header is Dictionary and image != null:
			native_surface_count += 1
			surface_received.emit(header, image)
	recovery_elapsed += delta
	if recovery_elapsed >= 120.0 and commands.is_empty():
		recovery_elapsed = 0.0
		_save_recovery()

func _ingest(payload: String) -> void:
	var messages: Variant = JSON.parse_string(payload)
	if not messages is Array: return
	for message: Dictionary in messages:
		if message.get("type") == "snapshot":
			generation = str(message.generation)
			snapshot_count += 1
			local_snapshot = message
			var present := {}
			for descriptor: Dictionary in message.modules: _request_panel(descriptor)
			for descriptor: Dictionary in message.modules: present[str(descriptor.id)] = true
			for id: String in panels.keys():
				if not id.begins_with("preview/") and not present.has(id): panels.erase(id)
		elif message.get("type") == "preview":
			panels.erase(str(message.descriptor.id))
			_request_panel(message.descriptor)
		elif message.get("type") == "ack" and not message.get("ok", false):
			push_error("Embedded command: " + str(message.get("error", "Unknown error")))
		message_received.emit(message)

func _request_panel(descriptor: Dictionary) -> void:
	var id := str(descriptor.id)
	var identity := str(descriptor.plugin) + "/" + str(descriptor.model)
	if panels.get(id) != identity: panel_requests[id] = identity

func _load_panels(budget: int) -> void:
	for id: String in panel_requests.keys().slice(0, budget):
		var image: Image = native.panel_image(id)
		if image == null:
			if native.last_error().contains("busy"): continue
			# Custom-drawn panels retain an explicit fallback until their native
			# compatibility renderer is integrated; avoid re-requesting each frame.
			panels[id] = panel_requests[id]
			panel_requests.erase(id)
			continue
		panels[id] = panel_requests[id]
		panel_requests.erase(id)
		surface_received.emit({"module": id, "generation": generation}, image)

func shutdown() -> bool:
	if closed: return true
	if connected and native != null:
		recovery_saved = _save_recovery()
		if not recovery_saved: push_error("Could not save embedded recovery patch: " + native.last_error())
	connected = false
	commands.clear()
	if audio_player != null: audio_player.stop()
	if audio_playback != null: audio_playback.stop()
	closed = native == null or native.close()
	return recovery_saved and closed

func _save_recovery() -> bool:
	var next_path := recovery_path + ".next.vcv"
	if not native.save_patch(next_path): return false
	if FileAccess.file_exists(recovery_path):
		if DirAccess.copy_absolute(recovery_path, recovery_path + ".bak") != OK: return false
	return DirAccess.rename_absolute(next_path, recovery_path) == OK

func _exit_tree() -> void:
	if not shutdown() and native != null:
		_close_when_idle(native, get_tree())

static func _close_when_idle(host, tree: SceneTree) -> void:
	# An in-flight audio callback owns the host until its final block completes.
	# Retain it outside the departing node and close on the original UI thread.
	for _attempt in range(30):
		if host.close(): return
		await tree.process_frame
	push_error("Embedded audio callback did not release its host during shutdown")
