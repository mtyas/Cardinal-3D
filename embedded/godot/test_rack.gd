extends SceneTree

func _initialize():
	_run.call_deferred()

func capture_manual(viewport: Viewport, name: String) -> void:
	var directory := OS.get_environment("CARDINAL_MANUAL_DIR")
	if directory.is_empty() or DisplayServer.get_name() == "headless": return
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(directory.path_join(name + ".png"))

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
	await capture_manual(root, "rack")
	var session = load("res://scripts/xr_session.gd").new()
	scene.add_child(session)
	session.host = scene
	session.headset = XRCamera3D.new()
	session.add_child(session.headset)
	session._make_ui()
	await process_frame
	session._menu_buttons("right", false, true)
	assert(session.main_menu.visible and session.ui_panel.visible, "B must show the embedded main menu")
	await capture_manual(session.ui_viewport, "main-menu")
	if not OS.get_environment("CARDINAL_MANUAL_DIR").is_empty():
		session._open_settings("audio")
		await capture_manual(session.ui_viewport, "audio-menu")
		session._open_settings("about")
		assert(scene.about_page.entries.size() > 100, "All release notices must be available in-app")
		await capture_manual(session.ui_viewport, "about-menu")
		session._close_ui()
		session._toggle_browser()
		scene.module_browser.search.text = "Fundamental"
		scene.module_browser._filter()
		scene.module_browser._reset_scroll()
		await create_timer(1.0).timeout
		await capture_manual(session.ui_viewport, "browser")
		session._close_ui()
		session._toggle_menu()
	if DisplayServer.get_name() != "headless" and not OS.get_environment("CARDINAL_MENU_TEST_IMAGE").is_empty():
		await process_frame
		await RenderingServer.frame_post_draw
		session.ui_viewport.get_texture().get_image().save_png(OS.get_environment("CARDINAL_MENU_TEST_IMAGE") + "-main.png")
	session.wrist_slider.value = 4.0
	assert(is_equal_approx(session.wrist_speed, 4.0), "Main menu must control wrist sensitivity")
	var saved_controls := ConfigFile.new()
	assert(saved_controls.load(session.interaction_path) == OK and saved_controls.get_value("knobs", "wrist_speed") == 4.0, "Wrist sensitivity must persist independently of audio settings")
	session._close_ui()
	var selected = scene.modules.values()[0]
	session._select_module({"view": selected, "pixel": Vector2(20, 8), "world": selected.global_position, "kind": "module"})
	session._toggle_menu(true)
	for _attempt in range(40):
		if scene.overlay.visible: break
		await create_timer(0.05).timeout
	assert(scene.overlay.visible and scene.overlay_mode == "menu", "Grip + B on a selected module must display its native menu in the embedded frontend")
	session._refresh_ui()
	assert(session.ui_panel.visible)
	assert(session.ui_rect == scene.overlay.get_global_rect().grow_individual(8, 52, 8, 8), "Module menus must include their top-right close button in the clickable rectangle")
	if DisplayServer.get_name() != "headless":
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var ui_image: Image = session.ui_viewport.get_texture().get_image()
		var center := Vector2i(session.ui_rect.get_center())
		if not OS.get_environment("CARDINAL_MENU_TEST_IMAGE").is_empty():
			ui_image.save_png(OS.get_environment("CARDINAL_MENU_TEST_IMAGE"))
			scene.overlay_texture.get_image().save_png(OS.get_environment("CARDINAL_MENU_TEST_IMAGE") + "-native.png")
		print("MENU TEXTURE: rect=", session.ui_rect, "; overlay=", scene.overlay.get_global_rect(), "; viewport=", scene.overlay.get_viewport().get_visible_rect())
		assert(ui_image != null and Rect2i(Vector2i.ZERO, ui_image.get_size()).has_point(center))
		assert(ui_image.get_pixelv(center).a > 0.05, "The menu must occupy the actual sampled floating UI texture, not only have a visible flag")
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
	var fresh_session = load("res://scripts/xr_session.gd").new()
	restored.add_child(fresh_session)
	fresh_session.host = restored
	fresh_session.headset = XRCamera3D.new()
	fresh_session.add_child(fresh_session.headset)
	fresh_session.spatial = Node3D.new()
	fresh_session.add_child(fresh_session.spatial)
	fresh_session.case_body = StaticBody3D.new()
	var case_collision := CollisionShape3D.new()
	case_collision.shape = BoxShape3D.new()
	fresh_session.case_body.add_child(case_collision)
	fresh_session.spatial.add_child(fresh_session.case_body)
	var layout = load("res://scripts/rack_layout.gd").new()
	fresh_session.add_child(layout)
	fresh_session.rack_layout = layout
	restored.rack_layout = layout
	layout.setup(fresh_session)
	layout.mode_button.button_pressed = true
	layout.add_case()
	fresh_session._make_ui()
	fresh_session._toggle_menu()
	fresh_session._request_new_rack()
	await capture_manual(fresh_session.ui_viewport, "new-rack-warning")
	assert(fresh_session.new_rack_dialog.visible and restored.modules.size() == 7 and layout.cases.size() == 2, "Opening New rack must warn without changing the current workspace")
	fresh_session.new_rack_dialog.hide()
	assert(restored.modules.size() == 7, "Cancel must preserve the patch")
	var preserved_path: String = restored.bridge.recovery_path.get_base_dir().path_join("saved-before-new.vcv")
	restored.bridge.send_command("save", {"path": preserved_path})
	for _attempt in range(40):
		if FileAccess.file_exists(preserved_path): break
		await create_timer(0.05).timeout
	assert(FileAccess.file_exists(preserved_path))
	var preserved_bytes := FileAccess.get_file_as_bytes(preserved_path)
	fresh_session._confirm_new_rack()
	for _attempt in range(40):
		if restored.modules.size() == 1 and layout.cases.size() == 1 and restored.immersive_environment.place == 7: break
		await create_timer(0.05).timeout
	assert(restored.modules.size() == 1 and restored.modules.values()[0].descriptor.model == "HostAudio2" and restored.snapshot.cables.is_empty(), "Confirmed New rack must contain only Cardinal Audio 2 and no cables")
	assert(layout.cases.size() == 1 and not layout.layout_mode and restored.immersive_environment.scenery.get_child_count() == 0, "New rack must reset to one locked case and empty surroundings")
	assert(FileAccess.get_file_as_bytes(preserved_path) == preserved_bytes, "New rack must never overwrite a saved patch")
	await capture_manual(fresh_session.ui_viewport, "new-rack")
	print("PASS: new rack warning/cancel, audio-only patch, one case, empty space and preserved saved patch")
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
