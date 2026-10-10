extends SceneTree

# Run with Godot --headless --path godot --script ../tests/frontend_navigation.gd.
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var view = load("res://scripts/main.gd").new()
	root.add_child(view)
	await process_frame
	view.bridge.set_process(false)
	view.bridge.connected = true
	var requests: int = view.bridge.next_id
	var before: Vector3 = view.camera.position
	var pan := InputEventPanGesture.new()
	pan.position = Vector2(700, 500)
	pan.delta = Vector2(2, 1)
	root.push_input(pan)
	check(not view.camera.position.is_equal_approx(before), "Two-finger pan must move the camera")
	var yaw: float = view.yaw
	pan.shift_pressed = true
	root.push_input(pan)
	check(view.yaw != yaw, "Shift + two fingers must orbit")
	var distance: float = view.distance
	var pinch := InputEventMagnifyGesture.new()
	pinch.position = pan.position
	pinch.factor = 1.2
	root.push_input(pinch)
	check(view.distance < distance, "Pinch must zoom")
	view.view_mode = 1
	var down := InputEventMouseButton.new()
	down.position = pan.position
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	root.push_input(down)
	yaw = view.yaw
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(750, 520)
	motion.relative = Vector2(50, 20)
	root.push_input(motion)
	check(view.yaw != yaw, "Orbit mode must support ordinary click-drag")
	down.pressed = false
	root.push_input(down)
	check(not view.navigation_drag and not view.orbiting, "Release must end camera navigation")
	check(view.bridge.next_id == requests, "Camera navigation must not send patch interactions")
	var color: Color = view.environment.background_color
	view.lighting_preset = 1
	view._apply_lighting()
	check(view.environment.background_color != color, "Lighting presets must change the environment")
	var energy: float = view.key_light.light_energy
	view.brightness = 1.5
	view._apply_lighting()
	check(is_equal_approx(view.key_light.light_energy, energy * 1.5), "Brightness must scale lighting")
	view.bridge.connected = false
	print("Frontend navigation and lighting: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
