extends SceneTree

var failures := 0
class CableProbe:
	extends "res://scripts/main.gd"
	var endpoints := []
	func _draw_wire(start: Vector3, end: Vector3, _color: Color, parent_node: Node3D) -> void:
		endpoints = [parent_node.to_global(start), parent_node.to_global(end)]
class Bridge:
	extends RefCounted
	var commands := []
	func send_command(command: String, fields := {}) -> void:
		commands.append({"command": command, "fields": fields})
class Host:
	extends Node3D
	var bridge := Bridge.new()
	var modules := {}
	var generation := "first"
	var snapshot := {}
	var module_browser := Control.new()
	var local_pending_cable := {}
	var dragging := false
	var wire_cursor := Vector3.ZERO
	var pending_updates := 0
	func _pending_wire() -> void: pending_updates += 1
	func _title_hit(hit: Dictionary) -> bool: return hit.pixel.y <= 32

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
func _initialize() -> void: call_deferred("run")
func joints(tracker: XRHandTracker, separation: float) -> void:
	tracker.has_tracking_data = true
	tracker.hand_tracking_source = XRHandTracker.HAND_TRACKING_SOURCE_UNOBSTRUCTED
	var positions := {XRHandTracker.HAND_JOINT_WRIST: Vector3.ZERO, XRHandTracker.HAND_JOINT_INDEX_FINGER_PHALANX_PROXIMAL: Vector3(0, 0, -0.1), XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP: Vector3(0, 0, -0.2), XRHandTracker.HAND_JOINT_THUMB_TIP: Vector3(separation, 0, -0.2)}
	for joint in positions:
		tracker.set_hand_joint_flags(joint, XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID | XRHandTracker.HAND_JOINT_FLAG_POSITION_TRACKED)
		tracker.set_hand_joint_transform(joint, Transform3D(Basis.IDENTITY, positions[joint]))
func pose(pressed: bool, position := Vector3.ZERO) -> Dictionary:
	return {"source": "hand", "pressed": pressed, "position": position, "origin": position, "direction": Vector3.FORWARD}
func controller_pose(pressed: bool, position: Vector3, rotation := Basis.IDENTITY) -> Dictionary:
	var sample := pose(pressed, position)
	sample.source = "controller"
	sample.basis = rotation
	return sample
func run() -> void:
	var hand = load("res://scripts/xr_hand_input.gd").new()
	var tracker := XRHandTracker.new()
	joints(tracker, 0.01)
	check(not hand.sample(tracker).pressed, "Initially closed fingers must not press")
	joints(tracker, 0.05)
	hand.sample(tracker)
	joints(tracker, 0.02)
	check(hand.sample(tracker).pressed, "Open then pinch must press")
	joints(tracker, 0.03)
	check(hand.sample(tracker).pressed, "Pinch hysteresis must prevent jitter")
	joints(tracker, 0.05)
	check(not hand.sample(tracker).pressed, "Opening must release")
	tracker.set_hand_joint_flags(XRHandTracker.HAND_JOINT_WRIST, XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID)
	check(hand.sample(tracker).is_empty(), "Untracked required joints must cancel")
	joints(tracker, 0.01)
	check(not hand.sample(tracker).pressed, "Recovery with closed fingers must not press")
	tracker.hand_tracking_source = XRHandTracker.HAND_TRACKING_SOURCE_CONTROLLER
	check(hand.sample(tracker).is_empty(), "Inferred controller hands must use controller actions")
	joints(tracker, 0.05)
	tracker.set_hand_joint_transform(XRHandTracker.HAND_JOINT_WRIST, Transform3D(Basis.IDENTITY, Vector3(NAN, 0, 0)))
	check(hand.sample(tracker).is_empty(), "Non-finite joint data must cancel")
	var host := Host.new()
	root.add_child(host)
	host.add_child(host.module_browser)
	host.module_browser.hide()
	var session = load("res://scripts/xr_session.gd").new()
	host.add_child(session)
	session.host = host
	session.spatial = Node3D.new()
	session.add_child(session.spatial)
	for side in ["left", "right"]:
		session.devices[side] = {"pressed": false, "source": "hand", "armed": false, "hand": load("res://scripts/xr_hand_input.gd").new()}
	var module = load("res://scripts/module_view.gd").new()
	module.descriptor = {"id": "1", "x": 0, "y": 0, "width": 90, "height": 380}
	host.add_child(module)
	host.modules["1"] = module
	var hit := {"kind": "module", "view": module, "pixel": Vector2(40, 100), "control": {"kind": "knob"}, "world": Vector3.ZERO}
	session.interact("left", pose(true), hit)
	session.interact("right", pose(true), hit)
	check(host.bridge.commands.size() == 1 and host.bridge.commands[0].command == "pointer", "Only one hand may own a native gesture")
	session.interact("left", pose(true, Vector3(0, 0.02, 0)), hit)
	check(host.bridge.commands[-1].command == "drag_delta" and is_equal_approx(host.bridge.commands[-1].fields.dy, -10), "Knob pinch must use Cardinal drag deltas")
	var other_hit := hit.duplicate()
	other_hit.pixel = Vector2(200, 250)
	session.interact("left", pose(false), other_hit)
	check(host.bridge.commands[-1].command == "release" and not host.dragging, "Releasing a knob over another control must not synthesize a final pointer jump")
	session.interact("left", controller_pose(false, Vector3(0, 0, 1)), hit)
	session.interact("left", controller_pose(true, Vector3(0, 0, 1)), hit)
	session.wrist_speed = 2.0
	check(not session.capture.move, "Holding a knob must never move the module")
	session.interact("left", controller_pose(true, Vector3(0, 0, 1), Basis(Vector3.FORWARD, PI / 2)), {})
	var coarse: float = host.bridge.commands[-1].fields.dy
	check(is_equal_approx(coarse, -PI / 2 * session.WRIST_PIXELS_PER_RADIAN * 2.0), "Wrist speed must scale coarse tuning even when the ray misses")
	check(session._visual_target("left", other_hit).pixel == hit.pixel, "The owning ray dot must stay on the captured knob")
	check(session._visual_target("right", other_hit).pixel == other_hit.pixel, "The other controller must retain its own aiming dot")
	session.interact("left", controller_pose(true, Vector3(0, 0, 1.1), Basis(Vector3.FORWARD, PI / 2)), other_hit)
	var fine: float = host.bridge.commands[-1].fields.dy
	check(is_equal_approx(fine, 0.0), "Controller distance must never interfere with wrist tuning")
	var fine_pose := controller_pose(true, Vector3(0, 0, 1.1), Basis(Vector3.FORWARD, PI / 2 + 0.2))
	fine_pose.grip = true
	session.interact("left", fine_pose, other_hit)
	check(is_equal_approx(host.bridge.commands[-1].fields.dy, -3.6), "Trigger plus grip must provide ten times finer wrist tuning")
	session.interact("left", controller_pose(false, Vector3(0, 0, 1.1)), other_hit)
	check(not session.fine_meter.visible, "Adjustment meter must hide on release")
	session.wrist_speed = 1.0
	check(host.bridge.commands[-1].command == "release", "Controller knob release must not jump to the current ray target")
	var surface := hit.duplicate()
	surface.control = {}
	surface.pixel = Vector2(57, 320)
	session.interact("left", controller_pose(true, Vector3(0, 0, 1)), surface)
	check(host.bridge.commands[-1].command == "pointer" and host.bridge.commands[-1].fields.phase == "down", "Unknown native surface controls must receive trigger clicks")
	session.interact("left", controller_pose(false, Vector3(0, 0, 1)), other_hit)
	check(host.bridge.commands[-1].fields.phase == "up" and host.bridge.commands[-1].fields.x == 57, "Surface release must stay on the captured target when aim drifts")
	hit.control = {"kind": "slider", "id": 1}
	session.interact("left", controller_pose(true, Vector3(0, 0, 1)), hit)
	session.interact("left", controller_pose(true, Vector3(0, 0, 1), Basis(Vector3.FORWARD, 0.2)), {})
	check(is_equal_approx(host.bridge.commands[-1].fields.dy, -18.0), "Faders must accept wrist rotation with the same sensitivity as knobs")
	check(session.fine_meter.visible, "Faders must show the fine-adjustment meter")
	session.interact("left", controller_pose(false, Vector3(0, 0, 1)), {})
	hit.control = {"kind": "knob"}
	session.origin = XROrigin3D.new()
	session.add_child(session.origin)
	session.headset = XRCamera3D.new()
	session.origin.add_child(session.headset)
	session.headset.position = Vector3(0.2, 1.6, 0.1)
	session._move_player(Vector2(0.1, 0), 0.1, 1.0)
	check(session.origin.position == Vector3.ZERO, "Thumbstick drift must stay inside the deadzone")
	session._move_player(Vector2(0, 1), 0, 1.0)
	check(is_equal_approx(session.origin.position.z, -session.MOVE_SPEED), "Forward movement must follow headset yaw at the configured speed")
	var before_vertical: Vector3 = session.origin.position
	session._move_player(Vector2(0, 1), 0, 1.0, true)
	check(is_equal_approx(session.origin.position.y - before_vertical.y, session.MOVE_SPEED) and is_equal_approx(session.origin.position.z, before_vertical.z), "Grip plus stick up must raise the view without continuing zoom")
	session._move_player(Vector2(0, -1), 0, 1.0, true)
	check(is_equal_approx(session.origin.position.y, before_vertical.y), "Grip plus stick down must lower the view")
	session.move_velocity = Vector3.ZERO
	var head_position: Vector3 = session.headset.global_position
	session._move_player(Vector2.ZERO, 1.0, 0.1)
	check(session.headset.global_position.is_equal_approx(head_position), "Smooth turning must rotate around the headset")
	var turned: Basis = session.origin.basis
	session._move_player(Vector2.ZERO, 1.0, 0.1)
	check(session.origin.basis.is_equal_approx(turned), "Stick navigation must never rotate the view")
	session.gesture_owner = "left"
	var player_position: Vector3 = session.origin.position
	session._move_player(Vector2(0, 1), 0, 1.0)
	check(session.origin.position == player_position, "Locomotion must pause during a captured gesture")
	session.gesture_owner = ""
	session.interact("left", pose(true), hit)
	session.interact("left", {}, {})
	check(host.bridge.commands[-1].command == "release" and session.gesture_owner.is_empty(), "Tracking loss must release gestures")
	session.interact("left", pose(true), hit)
	host.generation = "reload"
	session.interact("left", pose(true), hit)
	check(host.bridge.commands[-1].command == "release", "Patch reload must invalidate captured widgets")
	session.interact("left", pose(true), hit)
	host.modules.erase("1")
	session.interact("left", pose(true), hit)
	check(host.bridge.commands[-1].command == "release", "Module removal during pinch must release")
	host.modules["1"] = module
	hit.pixel.y = 10
	var before_move := host.bridge.commands.size()
	session.interact("left", pose(true), hit)
	check(host.bridge.commands.size() == before_move, "A header press must select locally without moving Cardinal")
	check(session._valid_selection() and module.selection_strip.visible, "Pressing the title must select and visibly mark the module")
	session.interact("left", pose(true, Vector3(0.02, 0, 0)), hit)
	check(host.bridge.commands.size() == before_move and session.move_ghost.visible and session.snapped_position == Vector2(15, 0), "Title drag must show a snapped ghost without moving the real module")
	session.interact("left", pose(false), hit)
	check(host.bridge.commands[-1].command == "move_end", "Module movement must end its undo gesture")
	check(host.bridge.commands[-2].command == "move_delta" and host.bridge.commands[-2].fields.dx == 15, "Release must commit the snapped ghost destination")
	var occupied = load("res://scripts/module_view.gd").new()
	occupied.descriptor = {"id": "2", "x": 90, "y": 0, "width": 90, "height": 380}
	host.add_child(occupied)
	host.modules["2"] = occupied
	check(session._nearest_free_position(module, Vector2(90, 0)) == Vector2(180, 0), "The ghost must use Cardinal's grid search to avoid occupied positions")
	check(session._insertion_positions(module, Vector2(90, 0))["2"] == Vector2(180, 0), "Inserting a module must preview its neighbor sliding aside")
	check(session._insertion_positions(module, Vector2(120, 0))["2"] == Vector2(30, 0), "Insertion must also make room to the left of the chosen slot")
	var aimed := pose(true, Vector3(0.25, -0.02, 1))
	check(session._rack_pointer(module, aimed).is_equal_approx(Vector2(125, 10)), "Controller aiming must intersect the rack independently of controller translation")
	hit.control = {}
	before_move = host.bridge.commands.size()
	session.interact("left", controller_pose(true, Vector3(0.08, -0.02, 1)), hit)
	session.interact("left", controller_pose(true, Vector3(0.26, -0.02, 1)), hit)
	check(session.snapped_position == Vector2(90, 0) and session.neighbor_ghosts["2"].visible, "A captured header must follow its ray and preview an occupied insertion slot")
	check(session._visual_target("left", hit).world.x > 0.2, "The destination pointer must move with the ghost instead of staying on the original header")
	check(host.bridge.commands.size() == before_move and module.position == Vector3.ZERO, "Insertion previews must never move live modules before release")
	session.interact("left", controller_pose(false, Vector3(0.26, -0.02, 1)), hit)
	check(host.bridge.commands[-2].fields.insert, "Release must commit native insertion instead of searching for empty space")
	var angled := controller_pose(true, Vector3(-0.11, -0.115, 1))
	angled.direction = Vector3(0.2, 0.1, -1).normalized()
	session.interact("left", angled, hit)
	session.interact("left", angled, hit)
	check(not session.move_ghost.visible and session.snapped_position == Vector2.ZERO, "An angled press must retain its ray-plane grab offset without jumping the ghost")
	angled.pressed = false
	session.interact("left", angled, hit)
	host.modules.erase("2")
	occupied.free()
	hit.pixel.y = 100
	hit.control = {}
	before_move = host.bridge.commands.size()
	session.interact("left", pose(true), hit)
	session.interact("left", pose(true, Vector3(0.02, 0, 0)), hit)
	session.interact("left", pose(false), hit)
	check(host.bridge.commands.size() == before_move + 3 and host.bridge.commands[-1].fields.phase == "up", "Surface clicks must remain captured through press, motion and release")
	hit.pixel.y = 100
	hit.control = {"kind": "port", "direction": "output", "id": 0}
	session.interact("left", pose(true), hit)
	hit.pixel.x = 80
	hit.control = {"kind": "port", "direction": "input", "id": 1}
	session.interact("left", pose(true, Vector3(0.01, 0, 0)), hit)
	check(host.local_pending_cable.direction == "output" and host.pending_updates > 0, "Cable preview must start locally without native pointer dragging")
	session.interact("left", pose(false), {})
	check(host.bridge.commands[-1].command == "patch_cable" and host.bridge.commands[-1].fields.input_port == 1, "A brief release tremor must directly patch the last compatible socket")
	hit.control.direction = "output"
	session.interact("left", pose(true), hit)
	check(not session._compatible_socket(hit), "A cable must not snap to a socket with the same direction")
	session.capture.cable.direction = "input"
	check(session._compatible_socket(hit), "Repatching an existing cable must follow its actual fixed endpoint")
	session.capture.cable.direction = "output"
	session.cable_target_time = Time.get_ticks_msec() - 200
	var before_cancel: int = host.bridge.commands.size()
	session.interact("left", pose(false), {})
	check(host.bridge.commands.size() == before_cancel, "An expired or incompatible socket must cancel the cable drop without patch changes")
	host.snapshot.cables = [{"id": "77", "input_module": "1", "input_port": 1, "output_module": "2", "output_port": 0}]
	hit.control = {"kind": "port", "direction": "input", "id": 1}
	session.interact("left", pose(true), hit)
	session.interact("left", pose(true), hit)
	session.interact("left", pose(false), {})
	check(host.bridge.commands[-1].command != "disconnect_cable", "Release tremor without pulling must preserve an existing cable")
	session.interact("left", pose(true), hit)
	session.interact("left", pose(true), hit)
	session.interact("left", pose(true, Vector3(0.06, 0, 0)), {})
	session.interact("left", pose(false, Vector3(0.06, 0, 0)), {})
	check(host.bridge.commands[-1].command == "disconnect_cable" and host.bridge.commands[-1].fields.cable_id == "77", "Pulling an input plug clear and releasing must unplug exactly the grabbed cable")
	session.interact("left", pose(true), hit)
	session.interact("left", pose(true, Vector3(0.06, 0, 0)), {})
	before_cancel = host.bridge.commands.size()
	session.cancel()
	check(host.bridge.commands.size() == before_cancel + 1 and host.bridge.commands[-1].command == "release", "Tracking cancellation must preserve the cable and only release the gesture")
	var count := host.bridge.commands.size()
	session.interact("left", pose(true), {"kind": "case", "world": Vector3.ZERO})
	session.interact("left", pose(true, Vector3(0.1, 0, 0)), {})
	session.interact("left", pose(false), {})
	check(session.spatial.position == Vector3.ZERO and host.bridge.commands.size() == count, "Performance mode must lock case placement without patch commands")
	check(session.selected_module.is_empty() and not module.selection_strip.visible, "Clicking the case must deselect the module")
	hit.control = {"kind": "knob"}
	session.interact("left", pose(true), hit)
	module.free()
	session.interact("left", pose(true), {})
	check(host.bridge.commands[-1].command == "release", "Freed module references must be safe")
	var view := CableProbe.new()
	root.add_child(view)
	await process_frame
	view.bridge.set_process(false)
	view.bridge.connected = true
	var ui_session = load("res://scripts/xr_session.gd").new()
	view.add_child(ui_session)
	ui_session.host = view
	ui_session.headset = XRCamera3D.new()
	ui_session.add_child(ui_session.headset)
	ui_session._make_ui()
	await process_frame
	ui_session._sync_layout()
	check(not ui_session.ui_panel.visible and ui_session.ui_viewport.transparent_bg, "VR must start without a permanent panel or opaque blank window")
	ui_session._menu_buttons("right", false, true)
	check(ui_session.main_menu.visible and ui_session.ui_panel.visible, "B must open the contextual main menu")
	ui_session._menu_buttons("right", false, true)
	check(ui_session.main_menu.visible, "Holding B must not repeatedly toggle the menu")
	await process_frame
	var main_close: Button = ui_session.main_menu.find_child("WindowClose", true, false)
	var close_at := main_close.get_global_rect().get_center()
	ui_session._ui_motion(close_at, false)
	ui_session._ui_button(close_at, true)
	ui_session._ui_button(close_at, false)
	check(not ui_session.main_menu.visible and not ui_session.ui_panel.visible, "The top-right main menu close button must accept controller clicks")
	view.settings_panel.show()
	ui_session.main_menu.hide()
	ui_session._refresh_ui()
	check(ui_session.ui_panel.visible, "Audio/view settings must retain the floating panel when the main menu closes")
	view.settings_panel.hide()
	ui_session._menu_buttons("right", false, false)
	ui_session._menu_buttons("right", true, false)
	check(view.module_browser.visible and not ui_session.main_menu.visible, "A must open the module browser instead of the main menu")
	ui_session._menu_buttons("right", false, false)
	ui_session._menu_buttons("right", true, false)
	check(not ui_session.ui_panel.visible, "Pressing A again must close the browser and remove its panel")
	ui_session._toggle_menu()
	await process_frame
	var undo: Button
	for button in ui_session.main_menu.find_children("*", "Button", true, false):
		if button is Button and button.text == "Undo": undo = button
	var requests: int = view.bridge.next_id
	var pixel := undo.get_global_rect().get_center()
	ui_session._ui_motion(pixel, false)
	ui_session._ui_button(pixel, true)
	ui_session._ui_button(pixel, false)
	check(view.bridge.next_id == requests + 1, "Hand pointer events must activate real floating UI buttons")
	var controls := [{"kind": "port", "id": 0, "direction": "output", "x": 45, "y": 100, "width": 15, "height": 15}]
	var first := {"id": "1", "plugin": "Test", "model": "Panel", "x": 0, "y": 0, "width": 90, "height": 380, "screens": [], "controls": controls}
	var second: Dictionary = first.duplicate(true)
	second.id = "2"
	second.x = 180
	second.controls[0].direction = "input"
	var wire := {"output_module": "1", "output_port": 0, "input_module": "2", "input_port": 0}
	view._on_message({"type": "snapshot", "generation": "xr", "modules": [first, second], "cables": [wire], "overlay_mode": "none"})
	ui_session._close_ui()
	ui_session._select_module({"kind": "module", "view": view.modules["1"], "pixel": Vector2(45, 10), "world": Vector3.ZERO})
	requests = view.bridge.next_id
	ui_session._toggle_menu()
	check(ui_session.main_menu.visible, "B must open the main menu even when a module is selected")
	ui_session._toggle_menu(true)
	check(view.bridge.next_id >= requests + 3 and not ui_session.main_menu.visible, "Grip + B must release gestures and send native right-button down/up for the selected module")
	check(view.modules["1"].selection_strip.visible, "The selected module must stay marked while opening its native menu")
	view.overlay_mode = "menu"
	view._on_surface({"module": "scene", "overlay_mode": "menu", "origin_x": 0, "origin_y": 0}, Image.create(220, 180, false, Image.FORMAT_RGBA8))
	ui_session._refresh_ui()
	await process_frame
	var context_close: Button = view.overlay.get_node("WindowClose")
	close_at = context_close.get_global_rect().get_center()
	check(ui_session.ui_rect.has_point(close_at), "The native context menu close button must lie inside the VR pointing surface")
	ui_session._ui_motion(close_at, false)
	ui_session._ui_button(close_at, true)
	ui_session._ui_button(close_at, false)
	check(not view.overlay.visible, "The context menu close button must dismiss the native menu through controller input")
	var rack_space := Node3D.new()
	view.add_child(rack_space)
	for node in [view.rack, view.rack_case, view.cables, view.pending_wire]: node.reparent(rack_space, false)
	rack_space.transform = Transform3D(Basis(Vector3.UP, 0.7), Vector3(3, 1, -2))
	view.cable_signature = ""
	view._rebuild_cables([wire])
	check(view.endpoints[0].is_equal_approx(view.modules["1"].port_position(0, "output")) and view.endpoints[1].is_equal_approx(view.modules["2"].port_position(0, "input")), "Spatial movement and rotation must keep cable endpoints on their sockets")
	view.dragging = true
	view.snapshot.pending_cable = {"module": "1", "port": 0, "direction": "output"}
	view.wire_cursor = Vector3(4, 2, -1)
	view._pending_wire()
	var preview: MeshInstance3D = view.pending_mesh
	var vertices: PackedVector3Array = preview.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	check(preview.to_global(vertices[-1]).distance_to(view.wire_cursor + rack_space.basis * Vector3(0, 0, 0.04)) < 0.004, "Pending cable tips must follow the world-space hand ray")
	view.wire_cursor += Vector3(0.01, 0, 0)
	view._pending_wire()
	check(view.pending_mesh == preview and view.pending_wire.get_child_count() == 1, "Cable motion must reuse a single lightweight preview mesh")
	view.dragging = false
	view._pending_wire()
	check(not preview.visible, "Releasing must hide the reusable preview")
	view.bridge.connected = false
	view.queue_free()
	print("XR hands, controls, cables and lifecycle: %s" % ("PASS" if failures == 0 else "FAIL"))
	host.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
