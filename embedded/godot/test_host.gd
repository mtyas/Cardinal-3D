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
	var panel: Image = host.panel_image("1")
	assert(panel != null and panel.get_width() > 100 and panel.get_height() > 500)
	assert(panel.get_pixel(panel.get_width() / 2, panel.get_height() / 2).a > 0.9)
	var messages = JSON.parse_string(host.messages_json(JSON.stringify({"op": "hello", "version": 1, "request": 1})))
	var models = 0
	for message in messages:
		if message.type == "catalog": models = message.models.size()
	var minimum_models := int(OS.get_environment("CARDINAL_EMBEDDED_MINIMUM_MODELS"))
	if minimum_models == 0: minimum_models = 190
	assert(models >= minimum_models, "Original registry must be available without TCP: " + str(models))
	if OS.get_environment("CARDINAL_EMBEDDED_REQUIRE_GRAPHICS") == "1":
		var surface_header := ""
		for _attempt in range(20):
			surface_header = host.render_surface()
			if not surface_header.is_empty(): break
			await create_timer(0.05).timeout
		assert(not surface_header.is_empty(), "Native GL drawing must produce a surface: " + host.last_error())
		var header = JSON.parse_string(surface_header)
		var artwork: Image = host.surface_image()
		assert(artwork != null and artwork.get_width() == header.width and artwork.get_height() == header.height)
		assert(artwork.get_width() > 100 and artwork.get_height() > 500)
		assert(artwork.get_pixel(artwork.get_width() / 2, artwork.get_height() / 2).a > 0.9)
		print("PASS: original native GL artwork rendered in-process")
		var generation := ""
		for message in messages:
			if message.type == "snapshot": generation = str(message.generation)
		var menu_batch := [{"op": "release", "request": 2}, {"op": "escape", "request": 3, "generation": generation}]
		for phase in ["down", "up"]:
			menu_batch.append({"op": "pointer", "request": 4,
				"generation": generation, "module": "1", "x": 20, "y": 8, "button": 1, "phase": phase})
		var response = JSON.parse_string(host.messages_json(JSON.stringify(menu_batch)))
		for message in response:
			if message.type == "ack": assert(message.ok, str(message))
			if message.type == "snapshot": assert(message.overlay_mode == "menu", "B-style batched right click must retain its menu")
		var menu_found := false
		for _attempt in range(30):
			var menu_text: String = host.render_surface()
			if not menu_text.is_empty():
				var menu_header = JSON.parse_string(menu_text)
				if menu_header.module == "scene":
					assert(menu_header.overlay_mode == "menu")
					var menu_image: Image = host.surface_image()
					assert(menu_image != null and menu_image.get_width() > 100 and menu_image.get_height() > 40)
					menu_found = true
					break
			await create_timer(0.05).timeout
		assert(menu_found, "Original module context menu must render without a desktop Cardinal UI")
		host.messages_json(JSON.stringify({"op": "escape", "request": 3, "generation": generation}))
		print("PASS: original module context menu rendered in-process")
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
	var realtime = player.get_stream_playback()
	# Device startup can take longer than one short timer on a cold GL backend.
	for _attempt in range(40):
		if realtime.get_playback_position() > 0.05: break
		await create_timer(0.05).timeout
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
	print("PASS: Cardinal DSP inside Godot; offline and real audio-thread playback; native patch roundtrip; direct %d-model catalog" % models)
	quit(0)
