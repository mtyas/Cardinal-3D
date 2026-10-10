extends Node
class_name CardinalBridgeClient

signal message_received(message: Dictionary)
signal surface_received(header: Dictionary, image: Image)
signal connection_changed(connected: bool)

const MAX_FRAME := 24 * 1024 * 1024
var peer := StreamPeerTCP.new()
var incoming := PackedByteArray()
var outgoing := PackedByteArray()
var connected := false
var retry := 0.0
var heartbeat := 0.0
var next_id := 1
var generation := ""
var port := 39413
var snapshot_count := 0

func _ready() -> void:
	if OS.has_environment("CARDINAL_3D_PORT"):
		port = int(OS.get_environment("CARDINAL_3D_PORT"))

func send_command(operation: String, data: Dictionary = {}) -> int:
	if not connected:
		return -1
	var command := data.duplicate(true)
	command["op"] = operation
	command["request"] = next_id
	command["generation"] = generation
	next_id += 1
	var payload := JSON.stringify(command).to_utf8_buffer()
	var frame := PackedByteArray()
	frame.resize(5)
	frame.encode_u32(0, payload.size() + 1)
	frame[4] = 1
	frame.append_array(payload)
	if outgoing.size() + frame.size() > 1024 * 1024:
		_drop()
		return -1
	outgoing.append_array(frame)
	return int(command["request"])

func _drop() -> void:
	peer.disconnect_from_host()
	incoming.clear()
	outgoing.clear()
	generation = ""
	if connected:
		connected = false
		connection_changed.emit(false)

func _process(delta: float) -> void:
	peer.poll()
	var status := peer.get_status()
	if status == StreamPeerTCP.STATUS_NONE or status == StreamPeerTCP.STATUS_ERROR:
		_drop()
		retry -= delta
		if retry <= 0:
			retry = 1.0
			peer.connect_to_host("127.0.0.1", port)
		return
	if status != StreamPeerTCP.STATUS_CONNECTED:
		return
	if not connected:
		peer.set_no_delay(true)
		connected = true
		connection_changed.emit(true)
		send_command("hello", {"version": 1, "token": OS.get_environment("CARDINAL_3D_TOKEN"), "surface_compression": "zstd"})
	heartbeat += delta
	if heartbeat >= 0.5:
		heartbeat = 0
		send_command("heartbeat")
	if not outgoing.is_empty():
		var sent := peer.put_partial_data(outgoing)
		if sent[0] != OK:
			_drop()
			return
		outgoing = outgoing.slice(sent[1])
	var available := mini(peer.get_available_bytes(), mini(8 * 1024 * 1024, MAX_FRAME + 4 - incoming.size()))
	if available > 0:
		var data := peer.get_partial_data(available)
		if data[0] != OK:
			_drop()
			return
		incoming.append_array(data[1])
	if incoming.size() > MAX_FRAME + 4:
		_drop()
		return
	var handled := 0
	var latest_snapshot := {}
	var latest_surfaces := {}
	while incoming.size() >= 4 and handled < 64:
		var length := incoming.decode_u32(0)
		if length < 1 or length > MAX_FRAME:
			_drop()
			return
		if incoming.size() < length + 4:
			break
		var kind := incoming[4]
		var payload := incoming.slice(5, length + 4)
		incoming = incoming.slice(length + 4)
		handled += 1
		if kind == 1:
			var message: Variant = JSON.parse_string(payload.get_string_from_utf8())
			if message is Dictionary:
				if message.get("type") == "snapshot":
					snapshot_count += 1
					generation = str(message["generation"])
					latest_snapshot = message
				else: message_received.emit(message)
		elif kind == 2 and payload.size() >= 4:
			var header_length := payload.decode_u32(0)
			if header_length > payload.size() - 4:
				_drop()
				return
			var header: Variant = JSON.parse_string(payload.slice(4, 4 + header_length).get_string_from_utf8())
			if not header is Dictionary or str(header.get("generation")) != generation:
				continue
			var width := int(header.get("width", 0))
			var height := int(header.get("height", 0))
			var pixels := payload.slice(4 + header_length)
			if width <= 0 or height <= 0 or width > 4096 or height > 4096: continue
			if width * height * 4 > 16 * 1024 * 1024: continue
			if header.get("encoding", "raw") == "zstd" or (header.get("encoding", "raw") == "raw" and pixels.size() == width * height * 4):
				latest_surfaces[str(header["module"])] = {"header": header, "pixels": pixels, "width": width, "height": height}
	# Apply live positions and control values before expensive texture uploads.
	if not latest_snapshot.is_empty(): message_received.emit(latest_snapshot)
	for surface: Dictionary in latest_surfaces.values():
		if str(surface.header.get("generation")) == generation:
			var pixels: PackedByteArray = surface.pixels
			if surface.header.get("encoding", "raw") == "zstd": pixels = pixels.decompress(surface.width * surface.height * 4, FileAccess.COMPRESSION_ZSTD)
			if pixels.size() == surface.width * surface.height * 4:
				surface_received.emit(surface.header, Image.create_from_data(surface.width, surface.height, false, Image.FORMAT_RGBA8, pixels))
