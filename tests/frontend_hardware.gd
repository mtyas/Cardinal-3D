extends SceneTree

var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func operations(view) -> Array:
	var frames: PackedByteArray = view.bridge.outgoing
	var result: Array = []
	var offset := 0
	while offset + 5 <= frames.size():
		var size := frames.decode_u32(offset)
		result.append(JSON.parse_string(frames.slice(offset + 5, offset + 4 + size).get_string_from_utf8()))
		offset += 4 + size
	view.bridge.outgoing.clear()
	return result

func run() -> void:
	var probe_source = FileAccess.get_file_as_string("res://../tests/magnet_probe.gd")
	var probe := GDScript.new()
	probe.source_code = probe_source
	check(probe.reload() == OK, "Magnet probe must compile")
	var view = probe.new()
	root.add_child(view)
	await process_frame
	view.bridge.set_process(false)
	var module := {"id": "10", "plugin": "Test", "model": "Panel", "x": 0, "y": 0, "width": 90, "height": 380, "screens": [{"kind": "display", "x": 5, "y": 150, "width": 80, "height": 70}], "controls": [{"id": 2, "kind": "knob", "physical": true, "label": "Frequency", "display": "440 Hz", "x": 45, "y": 100, "width": 30, "height": 30, "normalized": 0.5}]}
	var other: Dictionary = module.duplicate(true)
	module.controls[0]["body_color"] = "#dd6622"
	other["id"] = "11"
	other["x"] = 90
	var state := {"type": "snapshot", "generation": "1", "modules": [module, other], "cables": [], "overlay_mode": "none"}
	view._on_message(state)
	await physics_frame
	await physics_frame
	var original_bounds: Rect2 = view.rack_case.bounds
	check(original_bounds.size.x > 180 and original_bounds.size.y > 380, "Case must surround modules")
	var cheek = view.rack_case.get_child(1)
	view.rack_case.sync(state["modules"])
	check(view.rack_case.get_child(1) == cheek, "Unchanged layout must reuse case geometry")
	other["x"] = 300
	view.rack_case.sync(state["modules"])
	check(view.rack_case.bounds.end.x > original_bounds.end.x, "Case must grow when modules move")
	view.rack_case.sync([module])
	check(view.rack_case.bounds.size.x < original_bounds.size.x, "Case must shrink after removal")
	var panel = view.modules["10"]
	var artwork := Image.create(180, 760, false, Image.FORMAT_RGBA8)
	artwork.fill(Color.RED)
	panel.apply_surface(artwork)
	var original_texture: ImageTexture = panel.texture
	artwork.fill(Color.BLUE)
	panel.apply_surface(artwork)
	check(panel.texture == original_texture, "Same-size panel frames must reuse the existing texture")
	# The dummy headless renderer retains the initial image instead of uploading updates.
	if DisplayServer.get_name() != "headless":
		check(panel.texture.get_image().get_pixel(0, 0).is_equal_approx(Color.BLUE), "GPU texture updates must contain fresh panel pixels")
	var resized := Image.create(90, 380, false, Image.FORMAT_RGBA8)
	panel.apply_surface(resized)
	check(panel.texture == original_texture and panel.texture.get_width() == 90, "Changed panel dimensions must still resize the existing texture safely")
	var knob: Node3D = panel.knobs["2"].node
	check(knob.get_node("ColourCap").material_override.albedo_color.is_equal_approx(Color("#dd6622")), "Knob cap must preserve the colour supplied by the original native SVG")
	var marker: MeshInstance3D = knob.get_node("ValueIndicator")
	check(marker.material_override.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED and marker.position.z > 0.015, "The value marker must stay bright and in front of the knob cap")
	var white_data: Dictionary = module.duplicate(true)
	white_data.controls[0].body_color = "#ffffff"
	var white_view = load("res://scripts/module_view.gd").new()
	root.add_child(white_view)
	white_view.setup(white_data)
	check(white_view.knobs["2"].node.get_node("ValueIndicator").material_override.albedo_color == Color.BLACK, "White knobs must use a black position marker")
	white_view.queue_free()
	var changed: Dictionary = module.duplicate(true)
	changed.controls[0].normalized = 0.8
	panel.update_state(changed)
	check(is_equal_approx(knob.rotation.z, -lerpf(-2.6, 2.6, 0.8)), "Live normalized values must visibly rotate the knob marker")
	panel.update_state(module)
	check(view.header_panel.size.y <= 65 and not view.settings_panel.visible, "Header must occupy a single compact row with view settings hidden")
	var alternate: Dictionary = module["controls"][0].duplicate(true)
	alternate["id"] = 3
	alternate["visible"] = false
	module["controls"].append(alternate)
	var overlap = load("res://scripts/module_view.gd").new()
	module["controls"].append({"id": 4, "kind": "light", "physical": false, "x": 30, "y": 200, "width": 6, "height": 6, "emission_r": 0.0, "emission_g": 0.8, "emission_b": 0.2})
	view.rack.add_child(overlap)
	overlap.setup(module)
	var led_material: StandardMaterial3D = overlap.lights["4"].material_override
	check(led_material.emission.is_equal_approx(Color(0, 0.8, 0.2)), "Composite and multicolor LEDs must follow direct native RGB values")
	var dark: Dictionary = module.duplicate(true)
	dark.controls[-1].emission_g = 0.0
	dark.controls[-1].emission_b = 0.0
	overlap.update_state(dark)
	check(led_material.emission == Color.BLACK and led_material.albedo_color.r < 0.03, "An unlit sequencer LED must remain dark instead of showing an artificial minimum brightness")
	overlap.update_state(module)
	module["controls"].pop_back()
	check(not overlap.control_nodes["knob/3/"].visible and overlap.control_nodes["knob/2/"].visible, "Hidden alternate controls must not draw duplicate markers")
	module["controls"][0]["visible"] = false
	alternate["visible"] = true
	overlap.update_state(module)
	check(not overlap.control_nodes["knob/2/"].visible and overlap.control_nodes["knob/3/"].visible, "Native mode changes must swap the visible knob")
	module["controls"].pop_back()
	module["controls"][0]["visible"] = true
	overlap.queue_free()
	var live_texture := Image.create(180, 760, false, Image.FORMAT_RGBA8)
	panel.apply_surface(live_texture)
	var refreshed: Dictionary = state.duplicate(true)
	refreshed.generation = "2"
	view._on_message(refreshed)
	check(view.modules["10"] == panel and panel.texture != null, "Topology refreshes must preserve panel textures of unchanged modules")
	check(panel.screens.size() == 1 and panel.screens[0].display_material.get_shader_parameter("panel_texture") == panel.texture, "Screens must reuse the live native texture")
	var screen: Vector2 = view.camera.unproject_position(panel.to_global(Vector3(45 * 0.002, -100 * 0.002, 0)))
	var hit: Dictionary = view._hit(screen)
	check(not hit.is_empty(), "Module must remain pickable in its case")
	var snap: Dictionary = view._magnetic_hit(hit, screen + Vector2(5, 0))
	check(snap.has("control") and snap["control"]["id"] == 2, "Magnet must select nearby knob")
	check(view.control_focus.active and "Frequency" in view.tooltip.text, "Magnet must identify selected control visually")
	view._clear_focus()
	view._magnetic_hit(hit, screen + Vector2(5, 0), true)
	check(view.cursor_targets.size() == 1 and view.cursor_targets[0].distance_to(snap["screen"]) < 0.01, "Cursor must target the projected control, not the viewport origin")
	check(not view.cursor_latches[0].is_empty(), "Magnet must latch before cursor-generated motion can arrive")
	view._magnetic_hit(hit, snap["screen"], true)
	check(view.cursor_targets.size() == 1, "Synthetic motion at the snapped control must not snap again")
	view.bridge.connected = true
	view.bridge.outgoing.clear()
	var press := InputEventMouseButton.new()
	press.position = screen
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.alt_pressed = true
	view._unhandled_input(press)
	var commands := operations(view)
	check(commands.size() == 1 and commands[0]["op"] == "pointer" and not view.moving, "Alt-clicking a control must never move a module")
	press.pressed = false
	view._unhandled_input(press)
	operations(view)
	press.position = view.camera.unproject_position(panel.to_global(Vector3(45 * 0.002, -16 * 0.002, 0)))
	press.pressed = true
	view._unhandled_input(press)
	commands = operations(view)
	check(commands.size() == 1 and commands[0]["op"] == "move_begin" and view.moving, "Title drag must start native module movement")
	press.pressed = false
	view._unhandled_input(press)
	commands = operations(view)
	check(commands.size() == 1 and commands[0]["op"] == "move_end", "Title drag must finish native undo group")
	state["overlay_mode"] = "menu"
	view._on_message(state)
	check(not view.overlay.visible, "Menu must wait for its own surface")
	var image := Image.create(120, 80, false, Image.FORMAT_RGBA8)
	view._on_surface({"module": "scene", "overlay_mode": "menu", "origin_x": 400, "origin_y": 200}, image)
	check(view.overlay.visible and view.overlay.size == Vector2(120, 80), "Context menu must use compact crop dimensions")
	var pointer := InputEventMouseMotion.new()
	pointer.position = Vector2(20, 25)
	view._overlay_input(pointer)
	commands = operations(view)
	check(commands.size() == 1 and commands[0]["x"] == 420 and commands[0]["y"] == 225, "Cropped menu input must map back to native scene coordinates")
	state["overlay_mode"] = "none"
	view._on_message(state)
	state["overlay_mode"] = "menu"
	view._on_message(state)
	check(not view.overlay.visible, "Reopening menu must not flash an old cached surface")
	view.rack_case.sync([])
	check(view.rack_case.get_child_count() == 0, "Empty patch must remove the case")
	view.bridge.connected = false
	print("Case, magnet, title dragging and cropped menu: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
