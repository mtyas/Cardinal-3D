extends Node3D
class_name CardinalXRSession

const HandInput := preload("res://scripts/xr_hand_input.gd")
const SCALE := 0.002
const WRIST_PIXELS_PER_RADIAN := 90.0
const DISTANCE_PIXELS_PER_METRE := 60.0
const MOVE_SPEED := 0.65
const STICK_DEADZONE := 0.2
var host
var interface: OpenXRInterface
var origin: XROrigin3D
var headset: XRCamera3D
var spatial: Node3D
var ui_viewport: SubViewport
var ui_panel: MeshInstance3D
var case_body: StaticBody3D
var case_shape: BoxShape3D
var devices := {}
var gesture_owner := ""
var capture := {}
var last_position := Vector3.ZERO
var ui_position := Vector2.ZERO
var placed := false
var ui_placed := false
var layout_key := ""
var active := false
var last_hover := {}
var selected_module := {}
var move_ghost: MeshInstance3D
var proposed_position := Vector2.ZERO
var snapped_position := Vector2.ZERO
var move_start := Vector2.ZERO
var neighbor_ghosts := {}

func _insertion_positions(view: CardinalModuleView, wanted: Vector2) -> Dictionary:
	var position := (wanted / Vector2(15, 380)).round() * Vector2(15, 380)
	var left := []
	var right := []
	for other in host.modules.values():
		if other == view or not is_equal_approx(float(other.descriptor.y), position.y): continue
		if rack_layout != null and other.get_parent() != view.get_parent(): continue
		if float(other.descriptor.x) < position.x: left.append(other)
		else: right.append(other)
	left.sort_custom(func(a, b): return float(a.descriptor.x) < float(b.descriptor.x))
	right.sort_custom(func(a, b): return float(a.descriptor.x) < float(b.descriptor.x))
	left.reverse()
	var result := {str(view.descriptor.id): position}
	var cursor := position.x
	for other in left:
		if float(other.descriptor.x) + float(other.descriptor.width) <= cursor: break
		cursor -= float(other.descriptor.width)
		result[str(other.descriptor.id)] = Vector2(cursor, position.y)
	cursor = position.x + float(view.descriptor.width)
	for other in right:
		if float(other.descriptor.x) >= cursor: break
		result[str(other.descriptor.id)] = Vector2(cursor, position.y)
		cursor += float(other.descriptor.width)
	return result

func _rack_pointer(view: CardinalModuleView, sample: Dictionary) -> Variant:
	var parent := view.get_parent() as Node3D
	var normal := parent.global_basis.z.normalized()
	var direction: Vector3 = sample.direction
	var divisor := normal.dot(direction)
	if absf(divisor) < 0.001: return null
	var distance := normal.dot(parent.to_global(Vector3(0, 0, 0.04)) - sample.origin) / divisor
	if distance < 0 or distance > 5: return null
	var point := parent.to_local(sample.origin + direction * distance)
	return Vector2(point.x / SCALE, -point.y / SCALE) + view.get_meta("rack_offset", Vector2.ZERO)
var cable_target := {}
var cable_target_time := 0

func _cable_active() -> bool:
	return capture.get("kind", "") == "module" and capture.get("control", {}).get("kind", "") == "port" and not gesture_owner.is_empty()

func _compatible_socket(hit: Dictionary) -> bool:
	if hit.get("kind", "") != "module" or hit.get("control", {}).get("kind", "") != "port": return false
	var source: Dictionary = capture.get("cable", capture.get("control", {}))
	return hit.control.get("direction", "") != source.get("direction", "")

func _cable_drop_hit(hit: Dictionary) -> Dictionary:
	if _compatible_socket(hit):
		cable_target = hit.duplicate()
		cable_target_time = Time.get_ticks_msec()
		return hit
	# Absorb a brief aiming tremor while releasing, but never latch indefinitely.
	# Once an existing plug has been pulled clear, don't snap it back to its origin.
	if capture.get("cable_pulled", false) and not capture.get("replace_cable", "").is_empty() and not cable_target.is_empty():
		if str(cable_target.view.descriptor.id) == capture.module and int(cable_target.control.id) == int(capture.control.id): return {}
	if Time.get_ticks_msec() - cable_target_time <= 150 and is_instance_valid(cable_target.get("view")) and _compatible_socket(cable_target):
		return cable_target
	return {}

func _begin_cable(hit: Dictionary) -> void:
	var control: Dictionary = hit.control
	var fixed := {"module": str(hit.view.descriptor.id), "port": control.id, "direction": control.direction}
	if control.direction == "input":
		for cable: Dictionary in host.snapshot.get("cables", []):
			if str(cable.input_module) == fixed.module and int(cable.input_port) == int(fixed.port):
				capture.replace_cable = str(cable.id)
				fixed = {"module": str(cable.output_module), "port": cable.output_port, "direction": "output"}
				break
	capture.cable = fixed
	capture.cable_start_position = last_position
	capture.cable_pulled = false
	host.local_pending_cable = fixed
	host.wire_cursor = hit.world
	host.dragging = true
	host._pending_wire()

func _commit_cable(drop: Dictionary) -> void:
	var fixed: Dictionary = capture.cable
	var fields := {"replace_cable": capture.get("replace_cable", "")}
	var destination := {"module": str(drop.view.descriptor.id), "port": drop.control.id}
	var output: Dictionary = fixed if fixed.direction == "output" else destination
	var input: Dictionary = destination if fixed.direction == "output" else fixed
	fields.merge({"output_module": output.module, "output_port": output.port, "input_module": input.module, "input_port": input.port})
	host.bridge.send_command("patch_cable", fields)

func _track_cable_pull(sample: Dictionary) -> void:
	if not _cable_active() or capture.get("replace_cable", "").is_empty(): return
	var to_socket: Vector3 = capture.world - sample.origin
	var direction: Vector3 = sample.direction.normalized()
	var ray_distance := (to_socket - direction * to_socket.dot(direction)).length()
	if ray_distance > 0.045 or sample.position.distance_to(capture.cable_start_position) > 0.025:
		capture.cable_pulled = true

func _nearest_free_position(view: CardinalModuleView, wanted: Vector2) -> Vector2:
	var grid := Vector2(15, 380)
	var rounded := (wanted / grid).round() * grid
	var size := Vector2(float(view.descriptor.get("width", 90)), float(view.descriptor.get("height", 380)))
	for step in range(10000):
		var candidate := rounded + Vector2((-(step / 2) if step % 2 == 0 else step / 2 + 1) * 15, 0)
		var free := true
		for other in host.modules.values():
			if other == view: continue
			var data: Dictionary = other.descriptor
			if Rect2(candidate, size).intersects(Rect2(float(data.x), float(data.y), float(data.width), float(data.height))):
				free = false
				break
		if free: return candidate
	return move_start

func _begin_move_preview(view: CardinalModuleView) -> void:
	move_start = Vector2(float(view.descriptor.get("x", 0)), float(view.descriptor.get("y", 0)))
	proposed_position = move_start
	snapped_position = move_start
	move_ghost = MeshInstance3D.new()
	var panel := QuadMesh.new()
	panel.size = Vector2(float(view.descriptor.get("width", 90)), float(view.descriptor.get("height", 380))) * SCALE
	move_ghost.mesh = panel
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.35, 0.9, 1, 0.55)
	mat.albedo_texture = view.texture
	move_ghost.material_override = mat
	view.get_parent().add_child(move_ghost)
	_update_move_preview(view, Vector2.ZERO)
	move_ghost.hide()

func _update_move_preview(view: CardinalModuleView, delta: Vector2) -> void:
	proposed_position += delta
	var slots := _insertion_positions(view, proposed_position)
	snapped_position = slots[str(view.descriptor.id)]
	var size: Vector2 = (move_ghost.mesh as QuadMesh).size
	var local_position: Vector2 = snapped_position - view.get_meta("rack_offset", Vector2.ZERO)
	move_ghost.position = Vector3(local_position.x * SCALE + size.x / 2, -local_position.y * SCALE - size.y / 2, 0.045)
	move_ghost.visible = proposed_position.distance_to(move_start) > 3
	for id in neighbor_ghosts: neighbor_ghosts[id].hide()
	if not move_ghost.visible: return
	for id in slots:
		if id == str(view.descriptor.id): continue
		var other: CardinalModuleView = host.modules[id]
		if not neighbor_ghosts.has(id):
			var ghost := MeshInstance3D.new()
			var panel := QuadMesh.new()
			panel.size = Vector2(float(other.descriptor.width), float(other.descriptor.height)) * SCALE
			ghost.mesh = panel
			var mat := move_ghost.material_override.duplicate() as StandardMaterial3D
			mat.albedo_texture = other.texture
			ghost.material_override = mat
			view.get_parent().add_child(ghost)
			neighbor_ghosts[id] = ghost
		var ghost: MeshInstance3D = neighbor_ghosts[id]
		var panel: QuadMesh = ghost.mesh
		var slot: Vector2 = slots[id] - other.get_meta("rack_offset", Vector2.ZERO)
		ghost.position = Vector3(slot.x * SCALE + panel.size.x / 2, -slot.y * SCALE - panel.size.y / 2, 0.035)
		ghost.show()

func _clear_move_preview() -> void:
	for ghost in neighbor_ghosts.values(): ghost.queue_free()
	neighbor_ghosts.clear()
	if is_instance_valid(move_ghost): move_ghost.queue_free()
	move_ghost = null
var was_focused := false
var last_controller_basis := Basis.IDENTITY
var last_knob_distance := 0.0
var move_velocity := Vector3.ZERO
var main_menu: PanelContainer
var ui_collision: CollisionShape3D
var button_states := {}
var ui_rect := Rect2(0, 0, 1440, 900)
var wrist_speed := 1.0
var wrist_slider: HSlider
var wrist_label: Label
var interaction_settings := ConfigFile.new()
var interaction_path := ""
var fine_start_distance := 0.0
var fine_distance := 0.0
var fine_meter: Node3D
var fine_marker: MeshInstance3D
var fine_label: Label3D
var popup_repeat := 0.0
var popup_scrolled: PopupMenu
var popup_release := false
var rack_layout
var turn_velocity := 0.0
var tutorial

func _visible_popup(node: Node) -> PopupMenu:
	for child in node.get_children(true):
		var nested := _visible_popup(child)
		if nested != null: return nested
	if node is PopupMenu and node.visible: return node
	return null

func _window_bounds(node: Node) -> Rect2:
	var bounds := Rect2()
	for child in node.get_children(true):
		var next := _window_bounds(child)
		if next.has_area(): bounds = next if not bounds.has_area() else bounds.merge(next)
	if node is Window and node.visible:
		var rectangle := Rect2(Vector2(node.position), Vector2(node.size)).grow(8)
		bounds = rectangle if not bounds.has_area() else bounds.merge(rectangle)
	return bounds

func _scroll_ui(axis: float, delta: float) -> void:
	var popup := _visible_popup(ui_viewport)
	if absf(axis) < STICK_DEADZONE:
		popup_repeat = 0.0
		return
	if popup != null:
		popup_repeat -= delta
		if popup_repeat > 0: return
		popup_repeat = lerpf(0.25, 0.09, absf(axis))
		var direction := -1 if axis > 0 else 1
		var index := popup.get_focused_item()
		if index < 0: index = 0 if direction > 0 else popup.item_count - 1
		else: index = clampi(index + direction, 0, popup.item_count - 1)
		while index >= 0 and index < popup.item_count and (popup.is_item_disabled(index) or popup.is_item_separator(index)):
			index += direction
		if index >= 0 and index < popup.item_count:
			popup.set_focused_item(index)
			popup.scroll_to_item(index)
			popup_scrolled = popup
	elif host.settings_panel.visible and host.get("settings_scroll") != null:
		host.settings_scroll.scroll_vertical -= int(axis * 500.0 * delta)
	elif host.overlay.visible:
		var event := InputEventMouseButton.new()
		event.position = ui_position
		event.button_index = MOUSE_BUTTON_WHEEL_UP if axis > 0 else MOUSE_BUTTON_WHEEL_DOWN
		event.factor = absf(axis) * delta * 12.0
		event.pressed = true
		ui_viewport.push_input(event, true)

func _load_interaction_settings() -> void:
	var directory := OS.get_environment("CARDINAL_EMBEDDED_USER_DIR")
	interaction_path = directory.path_join("interaction.cfg") if not directory.is_empty() else "user://xr-interaction.cfg"
	interaction_settings.load(interaction_path)
	wrist_speed = clampf(float(interaction_settings.get_value("knobs", "wrist_speed", 1.0)), 0.1, 12.0)

func _set_wrist_speed(value: float) -> void:
	wrist_speed = clampf(value, 0.1, 12.0)
	wrist_label.text = "Wrist speed · %.1f×" % wrist_speed
	interaction_settings.set_value("knobs", "wrist_speed", wrist_speed)
	if interaction_settings.save(interaction_path) != OK: push_error("Could not save knob wrist speed")

func _meter_quad(size: Vector2, color: Color, position: Vector3) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = size
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	material.albedo_color = color
	node.material_override = material
	node.position = position
	fine_meter.add_child(node)
	return node

func _update_fine_meter() -> void:
	if fine_meter == null:
		fine_meter = Node3D.new()
		add_child(fine_meter)
		_meter_quad(Vector2(0.18, 0.014), Color("183449"), Vector3.ZERO)
		for x in [-0.09, 0.0, 0.09]: _meter_quad(Vector2(0.001, 0.021), Color("d0dce5"), Vector3(x, 0, 0.001))
		fine_marker = _meter_quad(Vector2(0.004, 0.024), Color("83e7ed"), Vector3(0, 0, 0.002))
		fine_label = Label3D.new()
		preload("res://scripts/clear_text.gd").apply(fine_label)
		fine_label.font_size = 30
		fine_label.pixel_size = 0.0006
		fine_label.no_depth_test = true
		fine_label.position = Vector3(0, 0.035, 0.003)
		fine_meter.add_child(fine_label)
	var facing := headset.global_basis if is_instance_valid(headset) else Basis.IDENTITY
	fine_meter.global_transform = Transform3D(facing, capture["world"] + facing * Vector3(0.15, 0.02, 0.06))
	fine_marker.position.x = clampf(fine_distance / 0.2, -1.0, 1.0) * 0.09
	var display := ""
	for control: Dictionary in capture.view.descriptor.get("controls", []):
		if str(control.get("id")) == str(capture.control.get("id")) and control.get("kind") in ["knob", "slider"]:
			display = str(control.get("display", ""))
			break
	fine_label.text = "Push ← Fine → Pull\n%+.1f cm%s" % [fine_distance * 100.0, " · " + display if not display.is_empty() else ""]
	fine_meter.show()

func setup(view) -> bool:
	host = view
	interface = XRServer.find_interface("OpenXR") as OpenXRInterface
	if interface == null or not interface.is_initialized():
		host.status_label.text = "OpenXR unavailable · connect Quest Link and select its OpenXR runtime, then relaunch VR"
		host.status_timer = 30
		return false
	origin = XROrigin3D.new()
	add_child(origin)
	headset = XRCamera3D.new()
	origin.add_child(headset)
	headset.current = true
	spatial = Node3D.new()
	add_child(spatial)
	for node in [host.rack, host.rack_case, host.cables, host.pending_wire]: node.reparent(spatial, false)
	case_body = StaticBody3D.new()
	case_body.set_meta("xr_case", true)
	spatial.add_child(case_body)
	var collision := CollisionShape3D.new()
	case_shape = BoxShape3D.new()
	collision.shape = case_shape
	case_body.add_child(collision)
	rack_layout = load("res://scripts/rack_layout.gd").new()
	add_child(rack_layout)
	host.rack_layout = rack_layout
	rack_layout.setup(self)
	_make_ui()
	for side in ["left", "right"]:
		var controller := XRController3D.new()
		controller.tracker = side + "_hand"
		controller.pose = "aim"
		controller.button_pressed.connect(func(action: String):
			if action in ["ax_button", "by_button"]: print("XR button event: ", side, " ", action))
		origin.add_child(controller)
		var ray := MeshInstance3D.new()
		ray.mesh = ImmediateMesh.new()
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color("83e7ed")
		ray.material_override = mat
		add_child(ray)
		var hand_mesh := MeshInstance3D.new()
		hand_mesh.mesh = ImmediateMesh.new()
		hand_mesh.material_override = mat
		origin.add_child(hand_mesh)
		var target := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.006
		sphere.height = 0.012
		target.mesh = sphere
		target.material_override = mat
		target.visible = false
		add_child(target)
		devices[side] = {"controller": controller, "hand": HandInput.new(), "ray": ray, "mesh": hand_mesh, "target": target, "pressed": false, "source": "", "armed": false}
	host.bridge.connection_changed.connect(func(connected: bool):
		if not connected: cancel())
	get_viewport().use_xr = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	active = true
	var refresh := interface.get_display_refresh_rate()
	Engine.physics_ticks_per_second = int(round(refresh)) if refresh >= 60 and refresh <= 144 else 90
	tutorial.start.call_deferred(true)
	return true

func _make_ui() -> void:
	ui_viewport = SubViewport.new()
	ui_viewport.size = Vector2i(1440, 900)
	ui_viewport.transparent_bg = true
	ui_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	ui_viewport.gui_embed_subwindows = true
	add_child(ui_viewport)
	for node in host.get_children():
		if node is CanvasLayer:
			# The floating viewport owns its UI directly; no inherited main-window
			# canvas attachment may keep menus out of this rendered texture.
			for content in node.get_children(): content.reparent(ui_viewport)
			node.queue_free()
	ui_panel = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.2, 0.75)
	ui_panel.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = ui_viewport.get_texture()
	ui_panel.material_override = mat
	add_child(ui_panel)
	var body := StaticBody3D.new()
	body.set_meta("xr_ui", true)
	ui_panel.add_child(body)
	var collision := CollisionShape3D.new()
	ui_collision = collision
	var box := BoxShape3D.new()
	box.size = Vector3(1.2, 0.75, 0.005)
	collision.shape = box
	body.add_child(collision)
	host.header_panel.hide()
	host.status_label.hide()
	for node in host.header_panel.get_parent().get_children():
		if node is Label: node.hide()
	main_menu = PanelContainer.new()
	main_menu.position = Vector2(510, 180)
	main_menu.custom_minimum_size = Vector2(420, 0)
	host.header_panel.get_parent().add_child(main_menu)
	var column := VBoxContainer.new()
	main_menu.add_child(column)
	var title := Label.new()
	title.text = "Cardinal 3D"
	column.add_child(title)
	_load_interaction_settings()
	wrist_label = Label.new()
	wrist_label.text = "Wrist speed · %.1f×" % wrist_speed
	column.add_child(wrist_label)
	wrist_slider = HSlider.new()
	wrist_slider.min_value = 0.1
	wrist_slider.max_value = 12.0
	wrist_slider.step = 0.1
	wrist_slider.value = wrist_speed
	wrist_slider.custom_minimum_size = Vector2(380, 42)
	wrist_slider.tooltip_text = "Slow for precise turns; fast for a full-range sweep with one wrist turn. Push/pull fine tuning keeps its own sensitivity."
	column.add_child(wrist_slider)
	wrist_slider.value_changed.connect(_set_wrist_speed)
	for entry in [
		["Rack management", func(): _open_settings("racks")],
		["Environment & graphics", func(): _open_settings("environment")],
		["Audio & MIDI devices", func(): _open_settings("audio")],
		["Browse modules (A)", _toggle_browser],
		["Open patch…", func(): host._patch_action(0)],
		["Save patch as…", func(): host._patch_action(1)],
		["Undo", func(): host.bridge.send_command("undo")],
		["Redo", func(): host.bridge.send_command("redo")],
		["Tutorial", func(): tutorial.start()],
		["Close (B)", _close_ui]]:
		var button := Button.new()
		button.text = entry[0]
		button.custom_minimum_size.y = 42
		button.pressed.connect(entry[1])
		column.add_child(button)
	main_menu.hide()
	var back := Button.new()
	back.text = "Back to main menu"
	back.custom_minimum_size.y = 44
	host.settings_title.get_parent().add_child(back)
	host.settings_title.get_parent().move_child(back, 1)
	back.pressed.connect(func(): host.settings_panel.hide(); main_menu.show(); _refresh_ui())
	tutorial = load("res://scripts/startup_tutorial.gd").new()
	ui_viewport.add_child(tutorial)
	tutorial.setup(self)
	_refresh_ui()

func _open_settings(section: String) -> void:
	cancel()
	main_menu.hide()
	host.show_settings(section)
	_refresh_ui()

func _refresh_ui() -> void:
	var visible_ui: bool = main_menu.visible or host.module_browser.visible or host.dialog.visible or host.overlay.visible or host.settings_panel.visible or (tutorial != null and tutorial.visible)
	ui_panel.visible = visible_ui
	ui_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if visible_ui else SubViewport.UPDATE_DISABLED
	ui_collision.disabled = not visible_ui
	ui_rect = Rect2(0, 0, 1440, 900)
	if tutorial != null and tutorial.visible:
		ui_rect = tutorial.get_global_rect().grow(8)
	elif main_menu.visible and not host.module_browser.visible and not host.dialog.visible and not host.overlay.visible and not host.settings_panel.visible:
		var menu_rect := main_menu.get_global_rect().grow(8)
		if menu_rect.has_area(): ui_rect = menu_rect
	elif host.overlay.visible and host.overlay_mode == "menu" and not host.module_browser.visible and not host.dialog.visible and not host.settings_panel.visible:
		ui_rect = host.overlay.get_global_rect().grow(8)
	elif host.settings_panel.visible and not main_menu.visible and not host.module_browser.visible and not host.dialog.visible and not host.overlay.visible:
		ui_rect = host.settings_panel.get_global_rect().grow(8)
	var window_bounds := _window_bounds(ui_viewport) if visible_ui else Rect2()
	if window_bounds.has_area(): ui_rect = ui_rect.merge(window_bounds)
	ui_rect = ui_rect.intersection(Rect2(0, 0, 1440, 900))
	var size := ui_rect.size * (1.2 / 1440.0)
	(ui_panel.mesh as QuadMesh).size = size
	(ui_collision.shape as BoxShape3D).size = Vector3(size.x, size.y, 0.005)
	var mat: StandardMaterial3D = ui_panel.material_override
	mat.uv1_scale = Vector3(ui_rect.size.x / 1440.0, ui_rect.size.y / 900.0, 1)
	mat.uv1_offset = Vector3(ui_rect.position.x / 1440.0, ui_rect.position.y / 900.0, 0)

func _place_ui() -> void:
	var facing := Basis(Vector3.UP, headset.global_rotation.y)
	ui_panel.transform = Transform3D(facing, headset.global_position + facing * Vector3(0, -0.05, -0.95))
	ui_placed = true

func _close_ui() -> void:
	cancel()
	if tutorial != null: tutorial.hide()
	main_menu.hide()
	host.module_browser.close_browser()
	host.settings_panel.hide()
	host.dialog.hide()
	host.bridge.send_command("escape")
	_refresh_ui()

func _toggle_menu(force_main := false) -> void:
	if tutorial != null and tutorial.visible: _close_ui(); return
	if host.overlay.visible: _close_ui(); return
	if main_menu.visible: _close_ui(); return
	if _valid_selection() and not force_main:
		_context_menu(selected_module)
		return
	cancel()
	host.module_browser.close_browser()
	host.bridge.send_command("escape")
	_place_ui()
	main_menu.show()
	_refresh_ui()

func _toggle_browser() -> void:
	if tutorial != null: tutorial.hide()
	if host.module_browser.visible: _close_ui(); return
	cancel()
	main_menu.hide()
	host.settings_panel.hide()
	host.bridge.send_command("escape")
	_place_ui()
	host.module_browser.show_browser()
	_refresh_ui()

func _menu_buttons(side: String, browse: bool, menu: bool, force_main := false) -> void:
	var previous: Dictionary = button_states.get(side, {"browse": false, "menu": false})
	if browse and not previous.browse:
		_toggle_browser()
		print("XR browser button received: ", side)
	if menu and not previous.menu:
		_toggle_menu(force_main)
		print("XR menu button received: ", side, "; main=", main_menu.visible, "; module=", host.overlay.visible, "; selected=", _valid_selection())
		_record_menu_frame()
	button_states[side] = {"browse": browse, "menu": menu}

func _record_menu_frame() -> void:
	if OS.get_environment("CARDINAL_3D_MENU_DIAGNOSTICS") != "1": return
	var directory := OS.get_environment("CARDINAL_EMBEDDED_USER_DIR")
	if directory.is_empty() or DisplayServer.get_name() == "headless": return
	# Capture only this app's floating UI, after its layout and texture update.
	await RenderingServer.frame_post_draw
	if not is_instance_valid(ui_viewport): return
	_refresh_ui()
	var record := {"main_visible": main_menu.is_visible_in_tree(), "module_visible": host.overlay.is_visible_in_tree(),
		"panel_visible": ui_panel.is_visible_in_tree(), "rect": str(ui_rect), "panel_position": str(ui_panel.global_position),
		"head_position": str(headset.global_position), "overlay_mode": host.overlay_mode}
	var file := FileAccess.open(directory.path_join("last-menu.json"), FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(record, "\t"))
	var image := ui_viewport.get_texture().get_image()
	if image != null and not image.is_empty(): image.save_png(directory.path_join("last-menu.png"))

func _sync_layout() -> void:
	if not selected_module.is_empty() and not _valid_selection():
		if is_instance_valid(selected_module.get("view")): selected_module.view.set_selected(false)
		selected_module.clear()
	if not ui_placed:
		_place_ui()
	if host.modules.is_empty(): return
	if not placed:
		var facing := Basis(Vector3.UP, headset.global_rotation.y)
		spatial.transform = Transform3D(facing, headset.global_position + facing * Vector3(0.25, -0.2, -1.1) - facing * host.target)
		placed = true
	if rack_layout != null:
		rack_layout.sync()
		return
	var bounds: Rect2 = host.rack_case.bounds
	var key := str(bounds)
	if key != layout_key and bounds.has_area():
		layout_key = key
		case_shape.size = Vector3(bounds.size.x * SCALE, bounds.size.y * SCALE, 0.01)
		case_body.position = Vector3(bounds.get_center().x * SCALE, -bounds.get_center().y * SCALE, -0.04)

func _sample(side: String) -> Dictionary:
	var device: Dictionary = devices[side]
	var tracker := XRServer.get_tracker("/user/hand_tracker/" + side) as XRHandTracker
	var hand: Dictionary = device["hand"].sample(tracker)
	var mesh: ImmediateMesh = device["mesh"].mesh
	mesh.clear_surfaces()
	if not hand.is_empty():
		device["armed"] = false
		_draw_hand(mesh, hand["points"])
		hand["origin"] = origin.to_global(hand["origin"])
		hand["direction"] = origin.global_basis * hand["direction"]
		hand["position"] = origin.to_global(hand["position"])
		hand["source"] = "hand"
		return hand
	var controller: XRController3D = device["controller"]
	if not controller.get_has_tracking_data():
		device["armed"] = false
		return {}
	var pressed := controller.get_float("trigger") > (0.3 if device["pressed"] else 0.7) or controller.is_button_pressed("trigger_click")
	if not device["armed"]:
		if not pressed: device["armed"] = true
		pressed = false
	return {"origin": controller.global_position, "direction": -controller.global_basis.z, "position": controller.global_position, "basis": controller.global_basis, "pressed": pressed, "source": "controller", "context": controller.is_button_pressed("ax_button")}

func _controller_knob_delta(sample: Dictionary) -> float:
	var current_basis: Basis = sample["basis"]
	var rotation := (last_controller_basis.inverse() * current_basis).get_rotation_quaternion()
	# Extract wrist roll around the pointing axis, independent of aiming yaw/pitch.
	var roll := wrapf(2.0 * atan2(rotation.z, rotation.w), -PI, PI)
	var distance: float = sample["position"].distance_to(capture["world"])
	var pixels := roll * WRIST_PIXELS_PER_RADIAN * wrist_speed - (distance - last_knob_distance) * DISTANCE_PIXELS_PER_METRE
	last_controller_basis = current_basis
	last_knob_distance = distance
	fine_distance = distance - fine_start_distance
	_update_fine_meter()
	return pixels

func _move_player(stick: Vector2, _unused_turn: float, delta: float, vertical := false) -> void:
	# Do not move the player under a held knob, cable, module or floating menu.
	if not gesture_owner.is_empty():
		move_velocity = Vector3.ZERO
		turn_velocity = 0.0
		return
	if host.module_browser.visible:
		move_velocity = Vector3.ZERO
		turn_velocity = 0.0
		host.module_browser.scroll_vr(stick.y, delta)
		return
	if is_instance_valid(ui_panel) and ui_panel.visible:
		move_velocity = Vector3.ZERO
		turn_velocity = 0.0
		_scroll_ui(stick.y, delta)
		return
	var amount := stick.length()
	var desired := Vector3.ZERO
	if amount > STICK_DEADZONE:
		var input := stick.normalized() * minf((amount - STICK_DEADZONE) / (1.0 - STICK_DEADZONE), 1.0)
		var facing := Basis(Vector3.UP, headset.global_rotation.y)
		desired = facing * (Vector3(0, input.y, 0) if vertical else Vector3(input.x, 0, -input.y)) * MOVE_SPEED
		if vertical:
			turn_velocity = lerpf(turn_velocity, -input.x * 0.9, 1.0 - exp(-12.0 * delta))
	if not vertical: turn_velocity = 0.0
	elif amount <= STICK_DEADZONE:
		turn_velocity = lerpf(turn_velocity, 0.0, 1.0 - exp(-12.0 * delta))
	if absf(turn_velocity) > 0.0001:
		var pivot := headset.global_position
		origin.rotate_y(turn_velocity * delta)
		origin.global_position += pivot - headset.global_position
	# Changing grip mode must not keep drifting along the previous axis.
	if vertical: move_velocity = Vector3(0, move_velocity.y, 0)
	else: move_velocity.y = 0
	var blend := 1.0 - exp(-12.0 * delta)
	move_velocity = move_velocity.lerp(desired, blend)
	origin.global_position += move_velocity * delta

func _draw_hand(mesh: ImmediateMesh, points: Dictionary) -> void:
	var chains := [[1, 2, 3, 4, 5], [1, 6, 7, 8, 9, 10], [1, 11, 12, 13, 14, 15], [1, 16, 17, 18, 19, 20], [1, 21, 22, 23, 24, 25], [6, 11, 16, 21]]
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for chain in chains:
		for index in range(chain.size() - 1):
			if points.has(chain[index]) and points.has(chain[index + 1]):
				mesh.surface_add_vertex(points[chain[index]])
				mesh.surface_add_vertex(points[chain[index + 1]])
	mesh.surface_end()

func _hit(from: Vector3, direction: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, from + direction * 5)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return {}
	var body: Object = hit["collider"]
	if body.has_meta("xr_ui"):
		var local := ui_panel.to_local(hit["position"])
		var size: Vector2 = (ui_panel.mesh as QuadMesh).size
		return {"kind": "ui", "pixel": ui_rect.position + Vector2((local.x / size.x + 0.5) * ui_rect.size.x, (0.5 - local.y / size.y) * ui_rect.size.y), "world": hit["position"]}
	if body.has_meta("xr_case"): return {"kind": "case", "rack_id": body.get_meta("rack_id", 0), "world": hit["position"]}
	if not body.has_meta("module_view"): return {}
	var view: CardinalModuleView = body.get_meta("module_view")
	var pixel := view.pixel_at(hit["position"])
	var closest := {}
	var separation := 24.0
	var patching := _cable_active()
	if patching: separation = 32.0
	for control: Dictionary in view.descriptor.get("controls", []) if pixel.y > 32 else []:
		if not control.get("visible", true) or not control["kind"] in ["knob", "slider", "switch", "button", "port", "custom"]: continue
		if patching and not _compatible_socket({"kind": "module", "control": control}): continue
		var candidate := Vector2(float(control["x"]), float(control["y"]))
		var distance := pixel.distance_to(candidate)
		if control.kind == "slider":
			var start_point := Vector2(float(control.get("start_x", candidate.x)), float(control.get("start_y", candidate.y)))
			var end_point := Vector2(float(control.get("end_x", candidate.x)), float(control.get("end_y", candidate.y)))
			var nearest := Geometry2D.get_closest_point_to_segment(pixel, start_point, end_point)
			distance = pixel.distance_to(nearest)
		if distance < separation:
			separation = distance
			closest = control
	if not closest.is_empty(): pixel = Vector2(float(closest["x"]), float(closest["y"]))
	var target := view.to_global(Vector3(pixel.x * SCALE, -pixel.y * SCALE, 0.04))
	return {"kind": "module", "view": view, "pixel": pixel, "control": closest, "world": target}

func _pointer(hit: Dictionary, phase: String, button: int = 0) -> void:
	if not is_instance_valid(hit.get("view")): return
	var pixel: Vector2 = hit["pixel"]
	host.bridge.send_command("pointer", {"module": str(hit["view"].descriptor["id"]), "x": pixel.x, "y": pixel.y, "phase": phase, "button": button, "mods": 0})
	host.wire_cursor = hit["world"]
	host._pending_wire()

func _ui_motion(pixel: Vector2, pressed: bool) -> void:
	if is_instance_valid(popup_scrolled) and popup_scrolled.visible: return
	var event := InputEventMouseMotion.new()
	event.position = pixel
	event.relative = pixel - ui_position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	ui_position = pixel
	ui_viewport.push_input(event, true)

func _ui_button(pixel: Vector2, pressed: bool) -> void:
	if popup_release and not pressed:
		popup_release = false
		return
	if pressed and is_instance_valid(popup_scrolled) and popup_scrolled.visible:
		var index := popup_scrolled.get_focused_item()
		if index >= 0:
			var popup := popup_scrolled
			popup_scrolled = null
			popup_release = true
			popup.hide()
			popup.index_pressed.emit(index)
			popup.id_pressed.emit(popup.get_item_id(index))
			return
	var event := InputEventMouseButton.new()
	event.position = pixel
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	ui_viewport.push_input(event, true)

func cancel() -> void:
	if rack_layout != null: rack_layout.end_grab()
	if fine_meter != null: fine_meter.hide()
	cable_target.clear()
	_clear_move_preview()
	if capture.get("kind", "") == "ui" and ui_viewport != null: _ui_button(ui_position, false)
	if host != null:
		host.local_pending_cable = {}
		host.bridge.send_command("release")
		host.dragging = false
		host._pending_wire()
	gesture_owner = ""
	capture.clear()
	for device: Dictionary in devices.values():
		if device.has("target"): device["target"].visible = false
		for visual in ["ray", "mesh"]:
			if device.has(visual): device[visual].mesh.clear_surfaces()
		device["pressed"] = false
		device["armed"] = false
		device["hand"].reset()

func interact(side: String, sample: Dictionary, hit: Dictionary) -> void:
	var device: Dictionary = devices[side]
	if sample.is_empty():
		if gesture_owner == side: cancel()
		device["pressed"] = false
		device["source"] = ""
		return
	if device["source"] != sample["source"]:
		if gesture_owner == side: cancel()
		device["source"] = sample["source"]
		device["pressed"] = false
	var pressed: bool = sample["pressed"]
	var start: bool = pressed and not device["pressed"]
	var finish: bool = not pressed and device["pressed"]
	device["pressed"] = pressed
	if not gesture_owner.is_empty() and gesture_owner != side: return
	if not capture.is_empty() and capture.get("kind") == "module":
		var view = capture["view"]
		if not is_instance_valid(view) or host.generation != capture["generation"] or not host.modules.has(capture["module"]):
			cancel()
			return
	_track_cable_pull(sample)
	if start and not hit.is_empty():
		cable_target.clear()
		gesture_owner = side
		capture = hit.duplicate()
		last_position = sample["position"]
		if sample["source"] == "controller" and sample.has("basis"):
			last_controller_basis = sample["basis"]
			last_knob_distance = sample["position"].distance_to(hit["world"])
			fine_start_distance = last_knob_distance
			fine_distance = 0.0
			if hit.get("control", {}).get("kind") in ["knob", "slider"]: _update_fine_meter()
		match hit["kind"]:
			"ui":
				_ui_motion(hit["pixel"], false)
				_ui_button(hit["pixel"], true)
			"case":
				if is_instance_valid(selected_module.get("view")): selected_module.view.set_selected(false)
				selected_module.clear()
				if rack_layout != null and rack_layout.layout_mode:
					rack_layout.begin_grab(hit.get("rack_id", 0), sample)
			"module":
				capture["generation"] = host.generation
				capture["module"] = str(hit["view"].descriptor["id"])
				capture["move"] = host._title_hit(hit)
				if capture["move"]:
					_select_module(hit)
					_begin_move_preview(hit["view"])
					var aim: Variant = _rack_pointer(hit.view, sample)
					capture.move_grab_offset = aim - move_start if aim is Vector2 else capture.pixel
				elif capture.get("control", {}).get("kind", "") == "port":
					_begin_cable(hit)
				elif not capture.get("control", {}).is_empty():
					host.dragging = true
					_pointer(hit, "down")
	elif finish and gesture_owner == side:
		if fine_meter != null: fine_meter.hide()
		match capture.get("kind", ""):
			"case":
				if rack_layout != null: rack_layout.end_grab()
			"ui": _ui_button(hit.get("pixel", ui_position) if hit.get("kind") == "ui" else ui_position, false)
			"module":
				if capture["move"]:
					if is_instance_valid(move_ghost) and move_ghost.visible and snapped_position != move_start:
						host.bridge.send_command("move_begin", {"module": capture["module"]})
						host.bridge.send_command("move_delta", {"dx": snapped_position.x - move_start.x, "dy": snapped_position.y - move_start.y, "insert": true})
						host.bridge.send_command("move_end")
					_clear_move_preview()
				elif capture.get("control", {}).is_empty(): pass
				elif capture.get("control", {}).get("kind", "") in ["knob", "slider"]: host.bridge.send_command("release")
				elif _cable_active():
					var drop := _cable_drop_hit(hit)
					if not drop.is_empty(): _commit_cable(drop)
					elif capture.get("cable_pulled", false) and not capture.get("replace_cable", "").is_empty():
						host.bridge.send_command("disconnect_cable", {"cable_id": capture.replace_cable, "input_module": capture.module, "input_port": capture.control.id})
				elif hit.get("kind") == "module": _pointer(hit, "up")
				else: host.bridge.send_command("release")
		gesture_owner = ""
		capture.clear()
		cable_target.clear()
		host.local_pending_cable = {}
		host.dragging = false
		host._pending_wire()
	elif pressed and gesture_owner == side:
		match capture.get("kind", ""):
			"case":
				if rack_layout != null and rack_layout.layout_mode: rack_layout.drag(sample, last_position)
			"ui":
				if hit.get("kind") == "ui": _ui_motion(hit["pixel"], true)
			"module":
				var view: CardinalModuleView = capture["view"]
				var delta: Vector3 = view.global_basis.inverse() * (sample["position"] - last_position)
				if capture["move"]:
					var aim: Variant = _rack_pointer(view, sample)
					if aim is Vector2: _update_move_preview(view, aim - capture.move_grab_offset - proposed_position)
					elif sample.source == "hand": _update_move_preview(view, Vector2(delta.x / SCALE, -delta.y / SCALE))
				elif capture.get("control", {}).is_empty(): pass
				elif capture.get("control", {}).get("kind", "") in ["knob", "slider"] and sample["source"] == "controller" and sample.has("basis"):
					host.bridge.send_command("drag_delta", {"dx": 0.0, "dy": _controller_knob_delta(sample), "mods": 0})
				elif capture.get("control", {}).get("kind", "") in ["knob", "slider"]:
					host.bridge.send_command("drag_delta", {"dx": delta.x / SCALE, "dy": -delta.y / SCALE, "mods": 0})
				elif _cable_active():
					var socket := _cable_drop_hit(hit)
					if not socket.is_empty():
						hit = socket
				elif hit.get("kind") == "module":
					_pointer(hit, "motion")
				else: host.bridge.send_command("drag_delta", {"dx": delta.x / SCALE, "dy": -delta.y / SCALE, "mods": 0})
				host.wire_cursor = hit.get("world", sample["origin"] + sample["direction"] * 0.8)
				host._pending_wire()
		last_position = sample["position"]
	elif gesture_owner.is_empty():
		if hit.get("kind") == "ui": _ui_motion(hit["pixel"], false)
		elif hit.get("kind") == "module":
			last_hover = hit.duplicate()
			last_hover["generation"] = host.generation
			_pointer(hit, "motion")

func _valid_selection() -> bool:
	return not selected_module.is_empty() and is_instance_valid(selected_module.get("view")) and selected_module.get("generation") == host.generation and host.modules.has(str(selected_module.view.descriptor.id))

func _select_module(hit: Dictionary) -> void:
	if is_instance_valid(selected_module.get("view")): selected_module.view.set_selected(false)
	selected_module = hit.duplicate()
	selected_module.generation = host.generation
	selected_module.view.set_selected(true)

func _context_menu(target := {}) -> void:
	if target.is_empty(): target = selected_module if _valid_selection() else last_hover
	if target.is_empty() or not is_instance_valid(target.get("view")) or target.get("generation") != host.generation: return
	cancel()
	if main_menu != null: main_menu.hide()
	host.module_browser.close_browser()
	_place_ui()
	host.menu_anchor = Vector2(300, 200)
	host.menu_surface_started = false
	_pointer(target, "down", 1)
	_pointer(target, "up", 1)

func _visual_target(side: String, hit: Dictionary) -> Dictionary:
	if gesture_owner != side or capture.get("kind", "") != "module" or not is_instance_valid(capture.get("view")):
		return hit
	if not capture.get("move", false) and not capture.get("control", {}).get("kind", "") in ["knob", "slider"]:
		return hit
	var target := capture.duplicate()
	if capture.get("move", false) and is_instance_valid(move_ghost) and move_ghost.visible:
		var slot: Vector2 = snapped_position - capture.view.get_meta("rack_offset", Vector2.ZERO)
		target.world = move_ghost.get_parent().to_global(Vector3((slot.x + capture.pixel.x) * SCALE, -(slot.y + capture.pixel.y) * SCALE, 0.05))
		return target
	var pixel: Vector2 = capture["pixel"]
	if capture.get("control", {}).get("kind") == "slider":
		for control in capture.view.descriptor.get("controls", []):
			if control.kind == "slider" and control.id == capture.control.id:
				pixel = Vector2(float(control.x), float(control.y))
				break
	target["world"] = capture["view"].to_global(Vector3(pixel.x * SCALE, -pixel.y * SCALE, 0.04))
	return target

func _physics_process(delta: float) -> void:
	if not active: return
	if interface.get_session_state() != OpenXRInterface.SESSION_STATE_FOCUSED or not host.bridge.connected:
		if was_focused: cancel()
		was_focused = false
		return
	_sync_layout()
	_refresh_ui()
	was_focused = true
	for side: String in devices:
		var controller: XRController3D = devices[side]["controller"]
		_menu_buttons(side, controller.is_button_pressed("ax_button"), controller.is_button_pressed("by_button"), controller.get_float("grip") > 0.5 or controller.is_button_pressed("grip_click"))
		var sample := _sample(side)
		var hit := {} if sample.is_empty() else _hit(sample["origin"], sample["direction"])
		interact(side, sample, hit)
		# A relative knob drag keeps its original target while the aiming ray moves.
		var visual_hit := _visual_target(side, hit)
		var mesh: ImmediateMesh = devices[side]["ray"].mesh
		mesh.clear_surfaces()
		var target: MeshInstance3D = devices[side]["target"]
		target.visible = not visual_hit.is_empty()
		if target.visible:
			target.global_position = visual_hit["world"]
			target.scale = Vector3.ONE * (1.5 if sample["pressed"] else 1.0)
		if not sample.is_empty():
			mesh.surface_begin(Mesh.PRIMITIVE_LINES)
			mesh.surface_add_vertex(sample["origin"])
			mesh.surface_add_vertex(visual_hit.get("world", sample["origin"] + sample["direction"] * 2))
			mesh.surface_end()
	var left: XRController3D = devices["left"]["controller"]
	var right: XRController3D = devices["right"]["controller"]
	var left_stick := left.get_vector2("primary") if left.get_has_tracking_data() else Vector2.ZERO
	var right_stick := right.get_vector2("primary") if right.get_has_tracking_data() else Vector2.ZERO
	var vertical := (left.get_has_tracking_data() and (left.get_float("grip") > 0.5 or left.is_button_pressed("grip_click"))) or (right.get_has_tracking_data() and (right.get_float("grip") > 0.5 or right.is_button_pressed("grip_click")))
	_move_player((left_stick + right_stick).limit_length(1.0), 0.0, delta, vertical)
