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
	var session = load("res://scripts/xr_session.gd").new()
	host.add_child(session)
	session.host = host
	session.spatial = Node3D.new()
	session.add_child(session.spatial)
	for side in ["left", "right"]:
		session.devices[side] = {"pressed": false, "source": "hand", "armed": false, "hand": load("res://scripts/xr_hand_input.gd").new()}
	var module = load("res://scripts/module_view.gd").new()
	module.descriptor = {"id": "1"}
	host.add_child(module)
	host.modules["1"] = module
	var hit := {"kind": "module", "view": module, "pixel": Vector2(40, 100), "control": {"kind": "knob"}, "world": Vector3.ZERO}
	session.interact("left", pose(true), hit)
	session.interact("right", pose(true), hit)
	check(host.bridge.commands.size() == 1 and host.bridge.commands[0].command == "pointer", "Only one hand may own a native gesture")
	session.interact("left", pose(true, Vector3(0, 0.02, 0)), hit)
	check(host.bridge.commands[-1].command == "drag_delta" and is_equal_approx(host.bridge.commands[-1].fields.dy, -10), "Knob pinch must use Cardinal drag deltas")
	session.interact("left", pose(false), hit)
	check(host.bridge.commands[-1].fields.phase == "up" and not host.dragging, "Unpinch must release native controls")
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
	session.interact("left", pose(true), hit)
	check(host.bridge.commands[-1].command == "move_begin", "Only the module title starts module movement")
	session.interact("left", pose(true, Vector3(0.02, 0, 0)), hit)
	check(host.bridge.commands[-1].command == "move_delta", "Title drag must use native module movement")
	session.interact("left", pose(false), hit)
	check(host.bridge.commands[-1].command == "move_end", "Module movement must end its undo gesture")
	hit.pixel.y = 100
	hit.control = {"kind": "port"}
	session.interact("left", pose(true), hit)
	hit.pixel.x = 80
	session.interact("left", pose(true, Vector3(0.01, 0, 0)), hit)
	check(host.bridge.commands[-1].fields.phase == "motion" and host.pending_updates > 0, "Cable pinch must forward socket motion and update its visual")
	session.interact("left", pose(false), hit)
	check(host.bridge.commands[-1].fields.phase == "up", "Cable drop must use Cardinal's native pointer release")
	var count := host.bridge.commands.size()
	session.interact("left", pose(true), {"kind": "case", "world": Vector3.ZERO})
	session.interact("left", pose(true, Vector3(0.1, 0, 0)), {})
	session.interact("left", pose(false), {})
	check(session.spatial.position.is_equal_approx(Vector3(0.1, 0, 0)) and host.bridge.commands.size() == count, "Grabbing the case changes scene placement without patch commands")
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
	check(ui_session.ui_panel.position.z < -0.5, "An empty rack must still expose the floating module browser")
	var undo: Button
	for button in view.toolbar.get_children():
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
	check(view.endpoints[1].is_equal_approx(view.wire_cursor), "Pending cable tips must follow the world-space hand ray")
	view.bridge.connected = false
	view.queue_free()
	print("XR hands, controls, cables and lifecycle: %s" % ("PASS" if failures == 0 else "FAIL"))
	host.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
