extends SceneTree

func _initialize():
	_run.call_deferred()

func _run():
	var host = ClassDB.instantiate("CardinalEmbeddedHost")
	assert(host != null, "Embedded extension was not registered")
	var resources = OS.get_environment("CARDINAL_EMBEDDED_RESOURCES")
	var scratch = OS.get_environment("CARDINAL_EMBEDDED_TEST_DIR")
	assert(not resources.is_empty() and not scratch.is_empty())
	assert(host.initialize(resources, scratch.path_join("settings"), 48000, 256), host.last_error())
	var path = scratch.path_join("tone.vcv")
	var patch = {"version": "2.4.1", "modules": [
		{"id": 1, "plugin": "Fundamental", "model": "VCO", "pos": [0, 0], "params": []},
		{"id": 2, "plugin": "Cardinal", "model": "HostAudio2", "pos": [10, 0], "params": []}],
		"cables": [{"id": 3, "outputModuleId": 1, "outputId": 0, "inputModuleId": 2, "inputId": 0, "color": "#ff5252"}]}
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(patch))
	file.close()
	assert(host.load_patch(path), host.last_error())
	var before = JSON.parse_string(host.patch_json())
	assert(before.modules.size() == 2 and before.cables.size() == 1)
	var messages = JSON.parse_string(host.messages_json(JSON.stringify({"op": "hello", "version": 1, "request": 1})))
	var models = 0
	for message in messages:
		if message.type == "catalog": models = message.models.size()
	assert(models == 190, "Original registry must be available without TCP")
	var energy = 0.0
	for block in range(375):
		var audio = host.render_block(256)
		assert(audio.size() == 256)
		for frame in audio:
			assert(is_finite(frame.x) and is_finite(frame.y))
			energy += frame.x * frame.x
	assert(energy / 96000 > 0.0001)
	# Exercise the actual native AudioStreamPlayback callback, not a GDScript
	# generator buffer. A second playback and teardown during mixing are refused.
	var stream = host.create_audio_stream()
	var playback = stream.instantiate_playback()
	playback.start()
	assert(playback.is_playing())
	assert(not host.close(), "Close must refuse an active audio playback")
	var second = stream.instantiate_playback()
	second.start()
	assert(not second.is_playing(), "Only one playback may process this engine")
	var mixed = playback.mix_audio(1.0, 256)
	assert(mixed.size() == 256)
	var mixed_energy = 0.0
	for frame in mixed: mixed_energy += frame.x * frame.x
	assert(mixed_energy > 0.01)
	assert(playback.get_playback_position() > 0.0)
	playback.stop()
	# Verify Godot's real audio thread invokes the callback with Dummy output.
	var player = AudioStreamPlayer.new()
	get_root().add_child(player)
	player.stream = stream
	player.play()
	await create_timer(0.15).timeout
	var realtime = player.get_stream_playback()
	assert(realtime.get_playback_position() > 0.05)
	player.stop()
	realtime.stop()
	await process_frame
	await process_frame
	player.queue_free()
	assert(host.save_patch(scratch.path_join("roundtrip.vcv")), host.last_error())
	assert(host.load_patch(scratch.path_join("roundtrip.vcv")), host.last_error())
	var after = JSON.parse_string(host.patch_json())
	assert(before.modules == after.modules and before.cables == after.cables)
	assert(host.close())
	print("PASS: Cardinal DSP inside Godot; offline and real audio-thread playback; native patch roundtrip; direct 190-model catalog")
	quit(0)
