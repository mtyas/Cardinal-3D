extends SceneTree

func _initialize():
	_run.call_deferred()

func _run():
	var scene = load("res://main.tscn").instantiate()
	get_root().add_child(scene)
	for _attempt in range(40):
		if scene.modules.size() == 6 and scene.bridge.audio_playback != null and scene.bridge.audio_playback.get_playback_position() > 0.05:
			if OS.get_environment("CARDINAL_EMBEDDED_REQUIRE_GRAPHICS") != "1" or scene.bridge.native_surface_count >= 2: break
		await create_timer(0.05).timeout
	assert(scene.bridge.connected, "Embedded backend must initialize")
	assert(scene.modules.size() == 6, "Native starter must appear in 3D: " + str(scene.modules.size()))
	assert(scene.snapshot.cables.size() == 5)
	for view in scene.modules.values():
		assert(view.face != null and view.texture != null, "Each starter panel must have original artwork")
	assert(scene.bridge.peer.get_status() == StreamPeerTCP.STATUS_NONE, "Embedded rack must not open TCP")
	assert(scene.bridge.audio_playback.get_playback_position() > 0.05)
	if OS.get_environment("CARDINAL_EMBEDDED_REQUIRE_GRAPHICS") == "1":
		assert(scene.bridge.native_surface_count >= 2, "Native drawing must update multiple modules")
	var audio_settings = scene.settings_panel.find_child("EmbeddedAudioSettings", true, false)
	assert(audio_settings != null and audio_settings.output_picker.item_count >= 1, "Embedded audio routing must be available")
	var session = load("res://scripts/xr_session.gd").new()
	scene.add_child(session)
	session.host = scene
	session.headset = XRCamera3D.new()
	session.add_child(session.headset)
	session._make_ui()
	await process_frame
	session._menu_buttons("right", false, true)
	assert(session.main_menu.visible and session.ui_panel.visible, "B must show the embedded main menu")
	session._close_ui()
	var selected = scene.modules.values()[0]
	session._select_module({"view": selected, "pixel": Vector2(20, 8), "world": selected.global_position, "kind": "module"})
	session._toggle_menu()
	for _attempt in range(40):
		if scene.overlay.visible: break
		await create_timer(0.05).timeout
	assert(scene.overlay.visible and scene.overlay_mode == "menu", "B on a selected module must display its native menu in the embedded frontend")
	session._refresh_ui()
	assert(session.ui_panel.visible)
	assert(session.ui_rect == scene.overlay.get_global_rect().grow(8), "Module menus must crop the floating panel to their actual clickable rectangle")
	session._close_ui()
	await process_frame
	print("PASS: embedded B main menu and selected-module menu through floating VR UI")
	scene.bridge.send_command("add", {"plugin": "Fundamental", "model": "VCA-1"})
	for _attempt in range(40):
		if scene.modules.size() == 7: break
		await create_timer(0.05).timeout
	assert(scene.modules.size() == 7)
	for _attempt in range(30):
		if scene.bridge.shutdown(): break
		await process_frame
	assert(scene.bridge.closed and scene.bridge.recovery_saved)
	assert(FileAccess.file_exists(scene.bridge.recovery_path), "Shutdown must preserve the changed patch")
	print("PASS: embedded 3D starter rack; six original panels; cables; native audio; no TCP")
	get_root().remove_child(scene)
	scene.queue_free()
	await process_frame
	var restored = load("res://main.tscn").instantiate()
	get_root().add_child(restored)
	for _attempt in range(40):
		if restored.modules.size() == 7 and restored.bridge.audio_playback != null and restored.bridge.audio_playback.get_playback_position() > 0.05: break
		await create_timer(0.05).timeout
	assert(restored.modules.size() == 7, "Recovery must reload the actual changed patch")
	for _attempt in range(30):
		if restored.bridge.shutdown(): break
		await process_frame
	assert(restored.bridge.closed and restored.bridge.recovery_saved)
	assert(FileAccess.file_exists(restored.bridge.recovery_path + ".bak"), "Replacing recovery must retain a previous copy")
	get_root().remove_child(restored)
	restored.queue_free()
	await process_frame
	print("PASS: embedded audio output settings and patch recovery across restart")
	quit(0)
