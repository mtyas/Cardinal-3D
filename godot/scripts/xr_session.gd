extends Node3D
class_name CardinalXRSession

const HandInput := preload("res://scripts/xr_hand_input.gd")
const SCALE := 0.002
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
var was_focused := false

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
	host._button("Control menu", _context_menu)
	host._button("↑", func(): host.module_browser.scrollbar.value -= host.module_browser.scrollbar.page)
	host._button("↓", func(): host.module_browser.scrollbar.value += host.module_browser.scrollbar.page)
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
	ui_viewport.transparent_bg = false
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
	mat.albedo_texture = ui_viewport.get_texture()
	ui_panel.material_override = mat
	add_child(ui_panel)
	var body := StaticBody3D.new()
	body.set_meta("xr_ui", true)
	ui_panel.add_child(body)
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.2, 0.75, 0.005)
	collision.shape = box
	body.add_child(collision)

func _sync_layout() -> void:
	if not ui_placed:
		var facing := Basis(Vector3.UP, headset.global_rotation.y)
		ui_panel.transform = Transform3D(facing, headset.global_position + facing * Vector3(-1.05, -0.10, -0.85))
		ui_placed = true
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
	return {"origin": controller.global_position, "direction": -controller.global_basis.z, "position": controller.global_position, "pressed": pressed, "source": "controller", "context": controller.is_button_pressed("ax_button")}

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
		return {"kind": "ui", "pixel": Vector2((local.x / 1.2 + 0.5) * 1440, (0.5 - local.y / 0.75) * 900), "world": hit["position"]}
	if body.has_meta("xr_case"): return {"kind": "case", "world": hit["position"]}
	if not body.has_meta("module_view"): return {}
	var view: CardinalModuleView = body.get_meta("module_view")
	var pixel := view.pixel_at(hit["position"])
	var closest := {}
	var separation := 24.0
	for control: Dictionary in view.descriptor.get("controls", []) if pixel.y > 32 else []:
		if not control.get("visible", true) or control["kind"] == "light": continue
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
	if capture.get("kind", "") == "ui" and ui_viewport != null: _ui_button(ui_position, false)
	if host != null:
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
	if start and not hit.is_empty():
		gesture_owner = side
		capture = hit.duplicate()
		last_position = sample["position"]
		match hit["kind"]:
			"ui":
				_ui_motion(hit["pixel"], false)
				_ui_button(hit["pixel"], true)
			"case": pass
			"module":
				capture["generation"] = host.generation
				capture["module"] = str(hit["view"].descriptor["id"])
				capture["move"] = host._title_hit(hit)
				if capture["move"]: host.bridge.send_command("move_begin", {"module": capture["module"]})
				else:
					host.dragging = true
					_pointer(hit, "down")
	elif finish and gesture_owner == side:
		match capture.get("kind", ""):
			"ui": _ui_button(hit.get("pixel", ui_position) if hit.get("kind") == "ui" else ui_position, false)
			"module":
				if capture["move"]: host.bridge.send_command("move_end")
				elif hit.get("kind") == "module": _pointer(hit, "up")
				else: host.bridge.send_command("release")
		gesture_owner = ""
		capture.clear()
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
				if capture["move"]: host.bridge.send_command("move_delta", {"dx": delta.x / SCALE, "dy": -delta.y / SCALE})
				elif capture.get("control", {}).get("kind", "") in ["knob", "slider"]:
					host.bridge.send_command("drag_delta", {"dx": delta.x / SCALE, "dy": -delta.y / SCALE, "mods": 0})
				elif hit.get("kind") == "module":
					_pointer(hit, "motion")
				else: host.bridge.send_command("drag_delta", {"dx": delta.x / SCALE, "dy": -delta.y / SCALE, "mods": 0})
				host.wire_cursor = sample["origin"] + sample["direction"] * 0.8
				host._pending_wire()
		last_position = sample["position"]
	elif gesture_owner.is_empty():
		if hit.get("kind") == "ui": _ui_motion(hit["pixel"], false)
		elif hit.get("kind") == "module":
			last_hover = hit.duplicate()
			last_hover["generation"] = host.generation
			_pointer(hit, "motion")

func _context_menu() -> void:
	if last_hover.is_empty() or not is_instance_valid(last_hover.get("view")) or last_hover.get("generation") != host.generation: return
	cancel()
	host.menu_anchor = Vector2(300, 200)
	host.menu_surface_started = false
	_pointer(last_hover, "down", 1)
	_pointer(last_hover, "up", 1)

func _physics_process(_delta: float) -> void:
	if not active: return
	if interface.get_session_state() != OpenXRInterface.SESSION_STATE_FOCUSED or not host.bridge.connected:
		if was_focused: cancel()
		was_focused = false
		return
	_sync_layout()
	was_focused = true
	for side: String in devices:
		var sample := _sample(side)
		var hit := {} if sample.is_empty() else _hit(sample["origin"], sample["direction"])
		var mesh: ImmediateMesh = devices[side]["ray"].mesh
		mesh.clear_surfaces()
		var target: MeshInstance3D = devices[side]["target"]
		target.visible = not hit.is_empty()
		if target.visible:
			target.global_position = hit["world"]
			target.scale = Vector3.ONE * (1.5 if sample["pressed"] else 1.0)
		if not sample.is_empty():
			mesh.surface_begin(Mesh.PRIMITIVE_LINES)
			mesh.surface_add_vertex(sample["origin"])
			mesh.surface_add_vertex(hit.get("world", sample["origin"] + sample["direction"] * 2))
			mesh.surface_end()
		interact(side, sample, hit)
