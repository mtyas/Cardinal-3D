extends SceneTree
var failures := 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
func _initialize() -> void: call_deferred("run")
func screenshot(viewport: Viewport, name: String) -> void:
	var directory := OS.get_environment("CARDINAL_UI_TEST_DIR")
	if DisplayServer.get_name() == "headless" or directory.is_empty(): return
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(directory.path_join(name + ".png"))
func run() -> void:
	var host = load("res://scripts/main.gd").new()
	root.add_child(host)
	await process_frame
	var session = load("res://scripts/xr_session.gd").new()
	host.add_child(session)
	session.host = host
	session.spatial = Node3D.new()
	session.add_child(session.spatial)
	session.origin = XROrigin3D.new()
	session.add_child(session.origin)
	session.headset = XRCamera3D.new()
	session.origin.add_child(session.headset)
	session.headset.position = Vector3(0.2, 1.6, 0.1)
	session.case_body = StaticBody3D.new()
	var collision := CollisionShape3D.new()
	collision.shape = BoxShape3D.new()
	session.case_body.add_child(collision)
	session.spatial.add_child(session.case_body)
	var layout = load("res://scripts/rack_layout.gd").new()
	session.add_child(layout)
	session.rack_layout = layout
	host.rack_layout = layout
	layout.setup(session)
	var descriptors := []
	for index in range(3):
		var descriptor := {"id": str(index + 1), "plugin": "Fundamental", "model": "VCO", "x": index * 90, "y": 0, "width": 90, "height": 380, "controls": []}
		descriptors.append(descriptor)
		var module = load("res://scripts/module_view.gd").new()
		host.rack.add_child(module)
		module.setup(descriptor)
		host.modules[descriptor.id] = module
	host.snapshot = {"modules": descriptors, "cables": []}
	layout.sync()
	layout.add_case()
	check(layout.cases.size() == 1, "Performance mode must reject case creation")
	layout.mode_button.button_pressed = true
	layout.add_case()
	check(layout.cases.size() == 2, "Layout mode must create a separate selectable case")
	check(layout.cases[1].root.position.x > layout.cases[0].case.bounds.end.x * layout.SCALE, "New cases must appear beside the selected rack")
	layout.add_case()
	layout.request_delete()
	check(layout.delete_dialog.visible and layout.cases.size() == 3, "Delete must show a warning without removing the case")
	layout.delete_dialog.hide()
	check(layout.cases.size() == 3, "Cancelling deletion must preserve the rack")
	layout.request_delete()
	layout.delete_dialog.hide()
	layout._confirm_delete()
	check(layout.cases.size() == 2, "Confirming an empty-case deletion must remove only that case")
	layout.active_case = 1
	session.selected_module = {"view": host.modules["2"], "generation": host.generation}
	layout.transfer_selected()
	check(host.modules["2"].get_parent() == layout.cases[1].modules, "Transferring a module must reparent its controls to the destination case")
	check(host.modules["2"].position == Vector3.ZERO, "The first module must anchor the new case instead of retaining a distant native offset")
	var previous: Vector3 = layout.cases[1].root.global_position
	layout.begin_grab(1, {"basis": Basis.IDENTITY})
	var delta := Vector3(0.2, 0.3, -0.4)
	layout.drag({"position": delta, "basis": Basis.IDENTITY}, Vector3.ZERO)
	check(layout.cases[1].root.global_position.is_equal_approx(previous + delta), "Rack translation must follow all three axes without flattening height or depth")
	var before_turn: Vector3 = layout.cases[1].root.global_position
	layout.drag({"position": delta, "basis": Basis(Vector3.UP, 0.3)}, delta)
	check(layout.cases[1].root.global_position.is_equal_approx(before_turn), "Turning a case in place must not orbit it around the controller")
	layout.drag({"position": Vector3(0.2, 0, 0), "basis": Basis(Vector3.UP, 0.3) * Basis(Vector3.RIGHT, 0.6)}, Vector3.ZERO)
	check(layout.cases[1].root.global_basis.y.is_equal_approx(Vector3.UP), "Case movement must reject pitch/roll and keep the rack upright")
	layout.end_grab()
	check(not layout.cases[1].root.global_position.is_equal_approx(previous), "Captured case must move and rotate")
	check(not layout.cases[1].root.global_basis.is_equal_approx(Basis.IDENTITY), "Case rotation must follow controller orientation")
	layout.mode_button.button_pressed = false
	previous = layout.cases[1].root.global_position
	layout.begin_grab(1, {"basis": Basis.IDENTITY})
	layout.drag({"position": Vector3(1, 0, 0)}, Vector3.ZERO)
	check(layout.cases[1].root.global_position == previous, "Performance mode must reject case translation")
	session._make_ui()
	session.main_menu.show()
	session._refresh_ui()
	await screenshot(session.ui_viewport, "main-menu")
	session._open_settings("racks")
	await screenshot(session.ui_viewport, "rack-menu")
	check(host.racks_column.visible and not host.audio_column.visible and not host.environment_column.visible and host.settings_scroll.scroll_vertical == 0, "Rack controls must have a separate top-level page")
	session._open_settings("environment")
	await screenshot(session.ui_viewport, "environment-menu")
	check(host.environment_column.visible and not host.audio_column.visible and not host.racks_column.visible, "Environment controls must be separate from devices and rack management")
	session._open_settings("audio")
	check(host.audio_column.visible and not host.environment_column.visible and not host.racks_column.visible, "Audio and MIDI must have their own page")
	session.tutorial.start()
	await screenshot(session.ui_viewport, "tutorial")
	for index in range(1, session.tutorial.PAGES.size()):
		session.tutorial.page = index
		session.tutorial._page()
		await screenshot(session.ui_viewport, "tutorial-%d" % (index + 1))
		check(session.tutorial.get_global_rect().end.y < 900, "Every illustrated tutorial page must fit inside the floating viewport")
	session.tutorial.page = 0
	session.tutorial._page()
	check(session.tutorial.visible and session.ui_panel.visible and not session.main_menu.visible and not host.settings_panel.visible, "Tutorial must open alone in the floating panel")
	session.tutorial.remember.button_pressed = false
	session.tutorial.finish()
	session.tutorial.start(true)
	check(not session.tutorial.visible, "Opting out must skip the next startup tutorial")
	session.tutorial.start()
	check(session.tutorial.visible, "The tutorial must remain available manually after opting out")
	session.tutorial.finish()
	host.settings_panel.show()
	session.main_menu.hide()
	var option := OptionButton.new()
	host.settings_column.add_child(option)
	for index in range(70): option.add_item("Device %d" % index)
	var popup := option.get_popup()
	popup.max_size = Vector2i(500, 350)
	popup.popup(Rect2i(30, 100, 400, 350))
	popup.set_focused_item(0)
	await process_frame
	for index in range(45): session._scroll_ui(-1, 0.3)
	check(popup.get_focused_item() == 45 and option.selected == 0, "Joystick must scroll/highlight long lists without changing devices until confirmation")
	session._ui_button(Vector2.ZERO, true)
	session._ui_button(Vector2.ZERO, false)
	check(option.selected == 45 and not popup.visible, "Trigger must confirm the highlighted device and close its list")
	host.settings_panel.hide()
	session._refresh_ui()
	session.move_velocity = Vector3.ZERO
	var head: Vector3 = session.headset.global_position
	session._move_player(Vector2(1, 0), 0, 0.2, true)
	check(session.headset.global_position.is_equal_approx(head) and not session.origin.basis.is_equal_approx(Basis.IDENTITY), "Grip turning must pivot around the headset without translating the user")
	for index in range(7):
		host.immersive_environment.place = index
		host.immersive_environment.rebuild()
		check(host.immersive_environment.scenery.get_child_count() > 1, "Each place must include real scenery")
		host.immersive_environment.hour = 0
		host.immersive_environment.update_light()
		var night: float = host.key_light.light_energy
		host.immersive_environment.hour = 12
		host.immersive_environment.update_light()
		check(host.key_light.light_energy > night, "Time of day must change scene lighting")
		if DisplayServer.get_name() != "headless" and not OS.get_environment("CARDINAL_SCENERY_TEST_DIR").is_empty():
			host.camera.global_position = Vector3(0, 0.2, 2)
			host.camera.look_at(Vector3(0, 0.2, -4))
			host.camera.fov = 75
			host.camera.current = true
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(OS.get_environment("CARDINAL_SCENERY_TEST_DIR").path_join("place-%d.png" % index))
	check(FileAccess.file_exists(layout.path), "Case transforms and membership must be saved")
	var patch_path: String = layout.path.get_base_dir().path_join("layout-check.vcv")
	layout.save(patch_path + ".3d.json")
	layout.restore_from(patch_path)
	check(layout.cases.size() == 2 and host.modules["2"].get_parent() == layout.cases[1].modules and not layout.layout_mode, "Reopening a saved patch must restore its separate cases and remain locked")
	print("XR layout, option scrolling, turning and environments: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
