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
	return Vector2(point.x / SCALE, -point.y / SCALE)
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
	move_ghost.position = Vector3(snapped_position.x * SCALE + size.x / 2, -snapped_position.y * SCALE - size.y / 2, 0.045)
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
		ghost.position = Vector3(slots[id].x * SCALE + panel.size.x / 2, -slots[id].y * SCALE - panel.size.y / 2, 0.035)
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
	_make_ui()
	for side in ["left", "right"]:
		var controller := XRController3D.new()
		controller.tracker = side + "_hand"
		controller.pose = "aim"
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
	return true

func _make_ui() -> void:
	ui_viewport = SubViewport.new()
	ui_viewport.size = Vector2i(1440, 900)
	ui_viewport.transparent_bg = true
	ui_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	ui_viewport.gui_embed_subwindows = true
	add_child(ui_viewport)
	for node in host.get_children():
		if node is CanvasLayer: node.reparent(ui_viewport)
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
	for entry in [
		["Browse modules (A)", _toggle_browser],
		["Open patch…", func(): host._patch_action(0)],
		["Save patch as…", func(): host._patch_action(1)],
		["Undo", func(): host.bridge.send_command("undo")],
		["Redo", func(): host.bridge.send_command("redo")],
		["Bring rack here", func(): placed = false],
		["Audio & view" if OS.get_environment("CARDINAL_3D_EMBEDDED") == "1" else "View & lighting", func(): host.settings_panel.visible = not host.settings_panel.visible],
		["Control context menu", _context_menu],
		["Close (B)", _close_ui]]:
		var button := Button.new()
		button.text = entry[0]
		button.custom_minimum_size.y = 42
		button.pressed.connect(entry[1])
		column.add_child(button)
	main_menu.hide()
	_refresh_ui()

func _refresh_ui() -> void:
	var visible_ui: bool = main_menu.visible or host.module_browser.visible or host.dialog.visible or host.overlay.visible
	ui_panel.visible = visible_ui
	ui_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if visible_ui else SubViewport.UPDATE_DISABLED
	ui_collision.disabled = not visible_ui
	ui_rect = Rect2(0, 0, 1440, 900)
	if main_menu.visible and not host.module_browser.visible and not host.dialog.visible and not host.overlay.visible and not host.settings_panel.visible:
		var menu_rect := main_menu.get_global_rect().grow(8)
		if menu_rect.has_area(): ui_rect = menu_rect
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
	main_menu.hide()
	host.module_browser.close_browser()
	host.settings_panel.hide()
	host.dialog.hide()
	host.bridge.send_command("escape")
	_refresh_ui()

func _toggle_menu() -> void:
	if host.overlay.visible: _close_ui(); return
	if main_menu.visible: _close_ui(); return
	if _valid_selection():
		_context_menu(selected_module)
		return
	cancel()
	host.module_browser.close_browser()
	host.bridge.send_command("escape")
	_place_ui()
	main_menu.show()
	_refresh_ui()

func _toggle_browser() -> void:
	if host.module_browser.visible: _close_ui(); return
	cancel()
	main_menu.hide()
	host.settings_panel.hide()
	host.bridge.send_command("escape")
	_place_ui()
	host.module_browser.show_browser()
	_refresh_ui()

func _menu_buttons(side: String, browse: bool, menu: bool) -> void:
	var previous: Dictionary = button_states.get(side, {"browse": false, "menu": false})
	if browse and not previous.browse: _toggle_browser()
	if menu and not previous.menu: _toggle_menu()
	button_states[side] = {"browse": browse, "menu": menu}

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
	var pixels := roll * WRIST_PIXELS_PER_RADIAN - (distance - last_knob_distance) * DISTANCE_PIXELS_PER_METRE
	last_controller_basis = current_basis
	last_knob_distance = distance
	return pixels

func _move_player(stick: Vector2, _unused_turn: float, delta: float) -> void:
	# Do not move the player under a held knob, cable, module or floating menu.
	if not gesture_owner.is_empty():
		move_velocity = Vector3.ZERO
		return
	if host.module_browser.visible:
		move_velocity = Vector3.ZERO
		host.module_browser.scroll_vr(stick.y, delta)
		return
	if is_instance_valid(ui_panel) and ui_panel.visible:
		move_velocity = Vector3.ZERO
		return
	var amount := stick.length()
	var desired := Vector3.ZERO
	if amount > STICK_DEADZONE:
		var input := stick.normalized() * minf((amount - STICK_DEADZONE) / (1.0 - STICK_DEADZONE), 1.0)
		var facing := Basis(Vector3.UP, headset.global_rotation.y)
		desired = facing * Vector3(input.x, 0, -input.y) * MOVE_SPEED
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
	if body.has_meta("xr_case"): return {"kind": "case", "world": hit["position"]}
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
	var event := InputEventMouseMotion.new()
	event.position = pixel
	event.relative = pixel - ui_position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	ui_position = pixel
	ui_viewport.push_input(event, true)

func _ui_button(pixel: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = pixel
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	ui_viewport.push_input(event, true)

func cancel() -> void:
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
		match hit["kind"]:
			"ui":
				_ui_motion(hit["pixel"], false)
				_ui_button(hit["pixel"], true)
			"case":
				if is_instance_valid(selected_module.get("view")): selected_module.view.set_selected(false)
				selected_module.clear()
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
		match capture.get("kind", ""):
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
			"case": spatial.global_position += sample["position"] - last_position
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
				elif capture.get("control", {}).get("kind", "") == "knob" and sample["source"] == "controller" and sample.has("basis"):
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
		target.world = move_ghost.get_parent().to_global(Vector3((snapped_position.x + capture.pixel.x) * SCALE, -(snapped_position.y + capture.pixel.y) * SCALE, 0.05))
		return target
	var pixel: Vector2 = capture["pixel"]
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
		_menu_buttons(side, controller.is_button_pressed("ax_button"), controller.is_button_pressed("by_button"))
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
	_move_player((left_stick + right_stick).limit_length(1.0), 0.0, delta)
