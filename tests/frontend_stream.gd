extends SceneTree

var events := []
func frame(kind: int, bytes: PackedByteArray) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(5)
	result.encode_u32(0, bytes.size() + 1)
	result[4] = kind
	result.append_array(bytes)
	return result
func snapshot(value: int) -> PackedByteArray:
	return frame(1, JSON.stringify({"type": "snapshot", "generation": "test", "value": value}).to_utf8_buffer())
func surface(value: int, compressed := false) -> PackedByteArray:
	var metadata := JSON.stringify({"module": "1", "generation": "test", "width": 512, "height": 512, "encoding": "zstd" if compressed else "raw"}).to_utf8_buffer()
	var bytes := PackedByteArray()
	bytes.resize(4)
	bytes.encode_u32(0, metadata.size())
	bytes.append_array(metadata)
	var pixels := PackedByteArray()
	pixels.resize(512 * 512 * 4)
	pixels.fill(value)
	if compressed: pixels = pixels.compress(FileAccess.COMPRESSION_ZSTD)
	bytes.append_array(pixels)
	return frame(2, bytes)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var server := TCPServer.new()
	assert(server.listen(0, "127.0.0.1") == OK)
	var bridge = load("res://scripts/bridge_client.gd").new()
	root.add_child(bridge)
	bridge.set_process(false)
	bridge.peer.connect_to_host("127.0.0.1", server.get_local_port())
	for i in range(20):
		bridge.peer.poll()
		if server.is_connection_available(): break
		await process_frame
	var sender := server.take_connection()
	assert(sender != null)
	for i in range(20):
		bridge.peer.poll()
		if bridge.peer.get_status() == StreamPeerTCP.STATUS_CONNECTED: break
		await process_frame
	bridge.message_received.connect(func(message): events.append(["snapshot", message.value]))
	bridge.surface_received.connect(func(_header, image): events.append(["surface", image.get_data()[0]]))
	# Feed a complete burst, including textures larger than the old per-frame budget.
	bridge.incoming.append_array(snapshot(1))
	bridge.incoming.append_array(surface(10))
	bridge.incoming.append_array(snapshot(2))
	bridge.incoming.append_array(surface(20))
	bridge._process(0.01)
	if events != [["snapshot", 2.0], ["surface", 20]]:
		push_error("Unexpected stream events: %s" % str(events))
		quit(1)
		return
	assert(bridge.incoming.is_empty())
	events.clear()
	bridge.incoming.append_array(surface(30, true))
	bridge.incoming.append_array(snapshot(3))
	bridge._process(0.01)
	assert(events == [["snapshot", 3.0], ["surface", 30]], "Compressed artwork must decode exactly and keep control updates first")
	bridge._drop()
	sender.disconnect_from_host()
	server.stop()
	bridge.queue_free()
	print("Snapshot and surface burst coalescing: PASS")
	quit()
