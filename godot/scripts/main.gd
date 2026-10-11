extends Node3D

const ModuleView := preload("res://scripts/module_view.gd")
const BridgeClient := preload("res://scripts/bridge_client.gd")
const EmbeddedClient := preload("res://scripts/embedded_client.gd")
const Hardware := preload("res://scripts/hardware.gd")
const RackCase := preload("res://scripts/rack_case.gd")
const ControlFocus := preload("res://scripts/control_focus.gd")
const ModuleBrowser := preload("res://scripts/module_browser.gd")
var module_browser
var xr_session
var bridge: CardinalBridgeClient
var camera: Camera3D
var environment: Environment
var key_light: DirectionalLight3D
var fill_light: DirectionalLight3D
var lighting_picker: OptionButton
var brightness_slider: HSlider
var brightness := 1.0
var lighting_preset := 0
var view_mode := 0
var navigation_drag := false

const LIGHTING_PRESETS := [
	{"name": "Studio", "background": "18222b", "ambient": "b9cedd", "ambient_energy": 0.85, "key": "fff4e6", "key_energy": 1.25, "fill": "b3d9ff", "fill_energy": 0.55},
	{"name": "Warm desk", "background": "231b18", "ambient": "c9aa8b", "ambient_energy": 0.65, "key": "ffce8e", "key_energy": 1.6, "fill": "bdd4ef", "fill_energy": 0.35},
	{"name": "Cool stage", "background": "0e182a", "ambient": "7696c9", "ambient_energy": 0.6, "key": "b7dbff", "key_energy": 1.8, "fill": "eab8ff", "fill_energy": 0.7},
	{"name": "Night", "background": "080c14", "ambient": "718399", "ambient_energy": 0.35, "key": "aac5ec", "key_energy": 0.65, "fill": "cc91ec", "fill_energy": 0.3}
]
var modules: Dictionary = {}
var rack: Node3D
var rack_case: CardinalRackCase
var cables: Node3D
var pending_wire: Node3D
var wire_cursor := Vector3.ZERO
var status_label: Label
var tooltip: Label
var overlay: TextureRect
var overlay_texture: ImageTexture
var overlay_mode := "none"
var overlay_surface_mode := "none"
var overlay_origin := Vector2.ZERO
var menu_anchor := Vector2(500, 300)
var menu_native_anchor := Vector2.ZERO
var menu_scale := 1.0
var menu_surface_started := false
var control_focus: Control
var magnet_enabled := true
var magnet_latched := ""
var focus_binding: Dictionary = {}
var header_panel: PanelContainer
var settings_panel: PanelContainer
var settings_scroll: ScrollContainer
var settings_column: VBoxContainer
var audio_column: VBoxContainer
var environment_column: VBoxContainer
var racks_column: VBoxContainer
var about_page: VBoxContainer
var settings_title: Label
var settings_icon: TextureRect
var settings_hint: Label
var settings_section := "audio"
var rack_layout
var immersive_environment
var pending_layout_load := {}
var layout_restore_path := ""
var settings_button: Button
var toolbar: HBoxContainer
var path_edit: LineEdit
var dialog: FileDialog
var generation := ""
var target := Vector3(0.75, -0.38, 0)
var distance := 2.5
var yaw := 0.0
var pitch := 0.05
var captured_module := ""
var dragging := false
var moving := false
var moving_origin := Vector2.ZERO
var orbiting := false
var panning := false
var snapshot: Dictionary = {}
var status_timer := 0.0
var cable_signature := ""
var pending_mesh: MeshInstance3D
var local_pending_cable := {}
var pending_signature := ""
var performance_elapsed := 0.0
var performance_frames := 0
var performance_worst := 0.0
var performance_previous_usec := 0

func _ready() -> void:
	bridge = EmbeddedClient.new() if OS.get_environment("CARDINAL_3D_EMBEDDED") == "1" else BridgeClient.new()
	add_child(bridge)
	bridge.message_received.connect(_on_message)
	bridge.surface_received.connect(_on_surface)
	bridge.connection_changed.connect(_on_connection)
	rack = Node3D.new()
	add_child(rack)
	rack_case = RackCase.new()
	add_child(rack_case)
	cables = Node3D.new()
	add_child(cables)
	pending_wire = Node3D.new()
	add_child(pending_wire)
	var world := WorldEnvironment.new()
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("53697e")
	sky_material.sky_horizon_color = Color("b6c4cf")
	sky_material.ground_bottom_color = Color("202731")
	sky_material.ground_horizon_color = Color("8795a0")
	sky.sky_material = sky_material
	environment.sky = sky
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	world.environment = environment
	add_child(world)
	key_light = DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-30, -25, 0)
	key_light.shadow_enabled = true
	key_light.directional_shadow_max_distance = 12.0
	key_light.shadow_bias = 0.03
	add_child(key_light)
	fill_light = DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(20, 45, 0)
	add_child(fill_light)
	_apply_lighting()
	camera = Camera3D.new()
	camera.fov = 40
	add_child(camera)
	_update_camera()
	_build_ui()
	immersive_environment = load("res://scripts/immersive_environment.gd").new()
	add_child(immersive_environment)
	immersive_environment.setup(self)
	get_tree().auto_accept_quit = false
	if OS.get_environment("CARDINAL_3D_XR") == "1":
		xr_session = load("res://scripts/xr_session.gd").new()
		add_child(xr_session)
		if not xr_session.setup(self): xr_session.queue_free(); xr_session = null

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		bridge.send_command("release")
		get_tree().quit()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT and bridge != null:
		if xr_session != null and xr_session.active: xr_session.cancel()
		_release()
		_clear_focus()
		orbiting = false
		panning = false
		navigation_drag = false

func _button(text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	toolbar.add_child(button)

func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = preload("res://scripts/ui_theme.gd").make()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(root)
	var panel := PanelContainer.new()
	header_panel = panel
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	root.add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	toolbar = HBoxContainer.new()
	column.add_child(toolbar)
	var title := Label.new()
	title.text = "CARDINAL  /  3D"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color("e6f7ff"))
	title.custom_minimum_size.x = 155
	toolbar.add_child(title)
	_button("Browse modules", func():
		_release()
		_clear_focus()
		bridge.send_command("escape")
		module_browser.show_browser())
	var browse: Button = toolbar.get_child(toolbar.get_child_count() - 1)
	browse.add_theme_stylebox_override("normal", preload("res://scripts/ui_theme.gd").box("195363", "55a9bd"))
	_button("Frame", _frame_rack)
	_button("View & lighting", func():
		_release()
		_clear_focus()
		settings_panel.visible = not settings_panel.visible)
	settings_button = toolbar.get_child(toolbar.get_child_count() - 1)
	settings_panel = PanelContainer.new()
	settings_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	settings_panel.position = Vector2(16, 62)
	settings_panel.visible = false
	root.add_child(settings_panel)
	settings_panel.custom_minimum_size = Vector2(600, 700)
	settings_panel.size = Vector2(600, 700)
	settings_scroll = ScrollContainer.new()
	settings_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var settings_shell := VBoxContainer.new()
	settings_panel.add_child(settings_shell)
	var settings_heading := HBoxContainer.new()
	settings_shell.add_child(settings_heading)
	settings_icon = TextureRect.new()
	settings_icon.custom_minimum_size = Vector2(40, 40)
	settings_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	settings_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	settings_heading.add_child(settings_icon)
	settings_title = Label.new()
	settings_title.text = "Audio & MIDI"
	settings_title.add_theme_font_size_override("font_size", 26)
	settings_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_title.add_theme_color_override("font_color", Color("62e4ca"))
	settings_heading.add_child(settings_title)
	settings_heading.add_child(preload("res://scripts/ui_theme.gd").close_button(func(): settings_panel.hide()))
	settings_hint = Label.new()
	settings_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settings_shell.add_child(settings_hint)
	settings_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	settings_shell.add_child(settings_scroll)
	settings_column = VBoxContainer.new()
	settings_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_scroll.add_child(settings_column)
	audio_column = VBoxContainer.new()
	environment_column = VBoxContainer.new()
	racks_column = VBoxContainer.new()
	for section in [audio_column, environment_column, racks_column]: settings_column.add_child(section)
	about_page = preload("res://scripts/about_page.gd").new()
	settings_column.add_child(about_page)
	about_page.setup(self)
	about_page.hide()
	environment_column.hide()
	racks_column.hide()
	if OS.get_environment("CARDINAL_3D_EMBEDDED") == "1":
		var audio_settings = load("res://scripts/embedded_audio_settings.gd").new()
		audio_settings.name = "EmbeddedAudioSettings"
		audio_settings.backend = bridge
		audio_column.add_child(audio_settings)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(spacer)
	var patch_menu := MenuButton.new()
	patch_menu.text = "Patch"
	toolbar.add_child(patch_menu)
	var popup := patch_menu.get_popup()
	popup.add_item("Open patch…", 0)
	popup.add_item("Save patch as…", 1)
	popup.add_separator("Examples")
	popup.add_item("Fundamental starter rack", 2)
	popup.add_item("Audible Instruments rack", 3)
	popup.add_separator()
	popup.add_item("Show original Cardinal UI", 4)
	popup.id_pressed.connect(_patch_action)
	_button("Undo", func(): bridge.send_command("undo"))
	_button("Redo", func(): bridge.send_command("redo"))
	var view_bar := HBoxContainer.new()
	environment_column.add_child(view_bar)
	var view_label := Label.new()
	view_label.text = "View"
	view_bar.add_child(view_label)
	var navigation := OptionButton.new()
	for mode in ["Play controls", "Orbit view", "Pan view"]:
		navigation.add_item(mode)
	navigation.item_selected.connect(func(index: int):
		_release()
		navigation_drag = false
		orbiting = false
		panning = false
		view_mode = index)
	view_bar.add_child(navigation)
	for entry in [{"name": "Front", "action": func():
		yaw = 0; pitch = 0; _frame_rack(); _update_camera()}]:
		var control := Button.new()
		control.text = entry["name"]
		control.pressed.connect(entry["action"])
		view_bar.add_child(control)
	var lighting_bar := HBoxContainer.new()
	environment_column.add_child(lighting_bar)
	var lighting_label := Label.new()
	lighting_label.text = "Lighting"
	lighting_label.hide()
	lighting_bar.add_child(lighting_label)
	lighting_picker = OptionButton.new()
	for preset in LIGHTING_PRESETS:
		lighting_picker.add_item(preset["name"])
	lighting_picker.item_selected.connect(func(index: int):
		lighting_preset = index
		_apply_lighting())
	lighting_bar.add_child(lighting_picker)
	lighting_picker.hide()
	var brightness_label := Label.new()
	brightness_label.text = "Exposure"
	lighting_bar.add_child(brightness_label)
	brightness_slider = HSlider.new()
	brightness_slider.min_value = 0.3
	brightness_slider.max_value = 2.0
	brightness_slider.step = 0.05
	brightness_slider.value = brightness
	brightness_slider.custom_minimum_size.x = 100
	brightness_slider.value_changed.connect(func(value: float):
		brightness = value
		_apply_lighting())
	lighting_bar.add_child(brightness_slider)
	var magnet := CheckButton.new()
	magnet.text = "Magnet"
	magnet.button_pressed = true
	magnet.toggled.connect(func(enabled: bool):
		magnet_enabled = enabled
		_clear_focus())
	toolbar.add_child(magnet)
	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.add_theme_color_override("font_color", Color("718999"))
	status_label.text = "  Waiting for Cardinal · run scripts/run.py"
	status_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	status_label.offset_left = -650
	status_label.offset_top = -28
	status_label.offset_right = -20
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(status_label)
	var instructions := Label.new()
	instructions.text = "Two fingers: pan  ·  Shift: orbit  ·  Pinch: zoom  ·  Drag titles to move"
	instructions.add_theme_font_size_override("font_size", 12)
	instructions.add_theme_color_override("font_color", Color("819baa"))
	instructions.position = Vector2(20, 0)
	instructions.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	instructions.offset_top = -32
	instructions.offset_left = 20
	root.add_child(instructions)
	tooltip = Label.new()
	tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip.add_theme_color_override("font_color", Color("b4f0ff"))
	tooltip.add_theme_color_override("font_shadow_color", Color("060b10"))
	tooltip.add_theme_constant_override("shadow_offset_x", 2)
	tooltip.add_theme_constant_override("shadow_offset_y", 2)
	control_focus = ControlFocus.new()
	control_focus.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(control_focus)
	root.add_child(tooltip)
	overlay = TextureRect.new()
	overlay.position = Vector2(70, 140)
	overlay.size = Vector2(1100, 650)
	overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	overlay.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	overlay.visible = false
	overlay.focus_mode = Control.FOCUS_ALL
	overlay.gui_input.connect(_overlay_input)
	root.add_child(overlay)
	var menu_close := preload("res://scripts/ui_theme.gd").close_button(func(): bridge.send_command("escape"); overlay.hide())
	overlay.add_child(menu_close)
	menu_close.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	menu_close.position = Vector2(overlay.size.x - 44, -44)
	overlay.resized.connect(func(): menu_close.position = Vector2(overlay.size.x - 44, -44))
	dialog = FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray(["*.vcv ; Cardinal patch"])
	dialog.use_native_dialog = false
	dialog.file_selected.connect(func(path: String):
		var saving := dialog.file_mode == FileDialog.FILE_MODE_SAVE_FILE
		var request := bridge.send_command("save" if saving else "load", {"path": path})
		if rack_layout != null:
			if saving: rack_layout.save(path + ".3d.json")
			else: pending_layout_load[request] = path)
	root.add_child(dialog)
	module_browser = ModuleBrowser.new()
	root.add_child(module_browser)
	module_browser.setup(bridge)
	module_browser.insert_requested.connect(func(plugin: String, model: String):
		bridge.send_command("add", {"plugin": plugin, "model": model}))

func show_settings(section: String) -> void:
	settings_section = section
	audio_column.visible = section == "audio"
	environment_column.visible = section == "environment"
	racks_column.visible = section == "racks"
	about_page.visible = section == "about"
	settings_title.text = {"audio": "Audio & MIDI", "environment": "Environment & graphics", "racks": "Rack management", "about": "About & licences"}.get(section, "Settings")
	settings_icon.texture = preload("res://scripts/ui_theme.gd").icon(section)
	settings_hint.text = {"audio": "Your sound and instruments · Use the stick to scroll long lists.", "environment": "Find your place · Choose scenery, daylight and picture quality.", "racks": "Arrange your space · Unlock Layout mode to move, turn or add cases."}.get(section, "")
	settings_scroll.scroll_vertical = 0
	settings_panel.show()

func _patch_action(id: int) -> void:
	match id:
		0: _file_dialog(false)
		1: _file_dialog(true)
		2:
			bridge.send_command("escape")
			bridge.send_command("starter")
		3:
			bridge.send_command("escape")
			bridge.send_command("audible_starter")
		4: bridge.send_command("overlay", {"enabled": overlay_mode != "full"})

func _file_dialog(save: bool) -> void:
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE if save else FileDialog.FILE_MODE_OPEN_FILE
	dialog.title = "Save Cardinal patch" if save else "Open Cardinal patch"
	if save:
		dialog.current_file = "Cardinal 3D.vcv"
	dialog.popup_centered_ratio(0.7)

func _on_connection(connected: bool) -> void:
	status_label.text = "  Connected · synchronizing…" if connected else "  Cardinal disconnected · reconnecting…"
	if not connected:
		if module_browser != null: module_browser.close_browser()
		_clear_focus()
		overlay.visible = false
		overlay_mode = "none"
		overlay_surface_mode = "none"
		cable_signature = ""
		captured_module = ""
		dragging = false
		moving = false
		_pending_wire()

func _on_message(message: Dictionary) -> void:
	match message.get("type", ""):
		"catalog":
			module_browser.set_catalog(message.get("models", []))
		"preview":
			if str(message.get("generation")) == generation:
				module_browser.receive_descriptor(message["descriptor"])
		"snapshot":
			var reset := generation != str(message["generation"])
			generation = str(message["generation"])
			if reset:
				cable_signature = ""
				_release()
				_clear_focus()
			var present := {}
			for descriptor: Dictionary in message.get("modules", []):
				var id := str(descriptor["id"])
				present[id] = true
				if modules.has(id) and (modules[id].descriptor.get("plugin") != descriptor.get("plugin") or modules[id].descriptor.get("model") != descriptor.get("model")):
					modules[id].queue_free()
					modules.erase(id)
				if not modules.has(id):
					var view := ModuleView.new()
					rack.add_child(view)
					view.setup(descriptor)
					modules[id] = view
				else:
					modules[id].update_state(descriptor)
			for id: String in modules.keys():
				if not present.has(id):
					_clear_focus()
					if captured_module == id:
						_release()
					modules[id].queue_free()
					modules.erase(id)
			snapshot = message
			if not focus_binding.is_empty() and modules.has(focus_binding["module"]):
				for control: Dictionary in modules[focus_binding["module"]].descriptor["controls"]:
					if str(control["id"]) == focus_binding["id"] and control["kind"] == focus_binding["kind"] and str(control.get("direction", "")) == focus_binding["direction"]:
						if control.get("visible", true): tooltip.text = _focus_text(control)
						else: _clear_focus()
						break
			if rack_layout != null:
				if not layout_restore_path.is_empty():
					rack_layout.restore_from(layout_restore_path)
					layout_restore_path = ""
				else: rack_layout.sync()
			else: rack_case.sync(message.get("modules", []))
			_rebuild_cables(message.get("cables", []))
			_pending_wire()
			if reset:
				_frame_rack()
			var next_mode := str(message.get("overlay_mode", "full" if message.get("overlay", false) else "none"))
			if next_mode != overlay_mode:
				_clear_focus()
				menu_surface_started = false
				overlay_surface_mode = "none"
				overlay_mode = next_mode
			# Never flash a cached full scene while waiting for a new context menu.
			overlay.visible = next_mode != "none" and overlay_surface_mode == next_mode
		"ack":
			var request := int(message.get("request", -1))
			if pending_layout_load.has(request):
				if message.get("ok", false): layout_restore_path = pending_layout_load[request]
				pending_layout_load.erase(request)
			if not message.get("ok", false):
				status_label.text = "  " + str(message.get("error", "Command failed"))
				status_timer = 5

func _on_surface(header: Dictionary, image: Image) -> void:
	var id := str(header["module"])
	if id.begins_with("preview/"):
		module_browser.receive_surface(id, image)
	elif id == "scene":
		var mode := str(header.get("overlay_mode", "full"))
		if mode != overlay_mode: return
		overlay_surface_mode = mode
		overlay_origin = Vector2(float(header.get("origin_x", 0)), float(header.get("origin_y", 0)))
		if overlay_texture == null:
			overlay_texture = ImageTexture.create_from_image(image)
			overlay.texture = overlay_texture
		else:
			overlay_texture.set_image(image)
		if mode == "menu":
			var viewport_size := get_viewport().get_visible_rect().size
			if not menu_surface_started:
				overlay.grab_focus()
				menu_native_anchor = overlay_origin
				menu_scale = minf(1.0, minf((viewport_size.x - 32) / image.get_width(), (viewport_size.y - 190) / image.get_height()))
				menu_surface_started = true
			overlay.size = Vector2(image.get_width(), image.get_height()) * menu_scale
			var position_hint := menu_anchor + (overlay_origin - menu_native_anchor) * menu_scale
			overlay.position = Vector2(clampf(position_hint.x, 16, maxf(16, viewport_size.x - overlay.size.x - 16)), clampf(position_hint.y, 130, maxf(130, viewport_size.y - overlay.size.y - 42)))
		else:
			overlay.position = Vector2(70, 140)
			overlay.size = Vector2(1100, 650)
		overlay.visible = true
	elif modules.has(id):
		modules[id].apply_surface(image)

func _rebuild_cables(descriptions: Array) -> void:
	if rack_layout != null and rack_layout.grabbed >= 0: return
	var positions := []
	for view: CardinalModuleView in modules.values():
		positions.append([view.descriptor["id"], str(view.global_transform)])
	var signature := JSON.stringify([descriptions, positions])
	if signature == cable_signature:
		return
	cable_signature = signature
	for child in cables.get_children():
		cables.remove_child(child)
		child.queue_free()
	for cable: Dictionary in descriptions:
		var output_id := str(cable["output_module"])
		var input_id := str(cable["input_module"])
		if not modules.has(output_id) or not modules.has(input_id):
			continue
		var start: Vector3 = modules[output_id].port_position(int(cable["output_port"]), "output")
		var end: Vector3 = modules[input_id].port_position(int(cable["input_port"]), "input")
		var color := Color(str(cable.get("color", "#dd9456")))
		_draw_wire(cables.to_local(start), cables.to_local(end), color, cables)

func _draw_wire(start: Vector3, end: Vector3, color: Color, parent_node: Node3D) -> void:
	if start.distance_to(end) < 0.0001:
		return
	var curve := Curve3D.new()
	curve.bake_interval = 0.012
	var sag := minf(start.distance_to(end) * 0.3, 0.2)
	curve.add_point(start + Vector3(0, 0, 0.042), Vector3.ZERO, Vector3(0, -sag, 0.14))
	curve.add_point(end + Vector3(0, 0, 0.042), Vector3(0, -sag, 0.14), Vector3.ZERO)
	var points := curve.get_baked_points()
	var tube := SurfaceTool.new()
	tube.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array = []
	var normals: Array = []
	for index in range(points.size()):
		var tangent: Vector3 = (points[mini(index + 1, points.size() - 1)] - points[maxi(index - 1, 0)]).normalized()
		var reference := Vector3.FORWARD if absf(tangent.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
		var normal := tangent.cross(reference).normalized()
		var binormal := tangent.cross(normal).normalized()
		var ring: Array = []
		var directions: Array = []
		for side in range(12):
			var direction := normal * cos(TAU * side / 12) + binormal * sin(TAU * side / 12)
			ring.append(points[index] + direction * 0.0036)
			directions.append(direction)
		rings.append(ring)
		normals.append(directions)
	for index in range(points.size() - 1):
		for side in range(12):
			var next := (side + 1) % 12
			for pair in [Vector2i(index, side), Vector2i(index + 1, next), Vector2i(index + 1, side), Vector2i(index, side), Vector2i(index, next), Vector2i(index + 1, next)]:
				tube.set_normal(normals[pair.x][pair.y])
				tube.set_uv(Vector2(float(pair.y) / 12, float(pair.x) / points.size()))
				tube.add_vertex(rings[pair.x][pair.y])
	Hardware.instance(parent_node, tube.commit(), Vector3.ZERO, Hardware.finish(color, 0, 0.32))
	for endpoint in [start, end]:
		Hardware.cylinder(parent_node, 0.0052, 0.012, endpoint - Vector3(0, 0, 0.009), Hardware.finish(Color("bbc3ca"), 0.95, 0.2))
		Hardware.cylinder(parent_node, 0.01, 0.024, endpoint + Vector3(0, 0, 0.007), Hardware.finish(color.darkened(0.12), 0.0, 0.4), 48, 0.88)
		Hardware.ring(parent_node, 0.0085, 0.0105, endpoint - Vector3(0, 0, 0.003), Hardware.finish(Color("b3bcc5"), 0.9, 0.25))
		Hardware.cylinder(parent_node, 0.0065, 0.018, endpoint + Vector3(0, 0, 0.027), Hardware.finish(color, 0, 0.5), 32, 0.65)
		for index in range(3):
			Hardware.ring(parent_node, 0.0048, 0.0068 - index * 0.0004, endpoint + Vector3(0, 0, 0.02 + index * 0.006), Hardware.finish(color.darkened(0.18), 0, 0.5))

func _pending_wire() -> void:
	var pending: Dictionary = local_pending_cable if not local_pending_cable.is_empty() else snapshot.get("pending_cable", {})
	var id := str(pending.get("module", ""))
	if not dragging or not modules.has(id):
		if is_instance_valid(pending_mesh): pending_mesh.hide()
		pending_signature = ""
		return
	var start: Vector3 = modules[id].port_position(int(pending["port"]), str(pending["direction"]))
	var signature := str([start, wire_cursor, pending.get("color", "#e39756")])
	if signature == pending_signature: return
	pending_signature = signature
	if not is_instance_valid(pending_mesh):
		pending_mesh = MeshInstance3D.new()
		pending_mesh.mesh = ImmediateMesh.new()
		pending_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		pending_mesh.material_override = mat
		pending_wire.add_child(pending_mesh)
	pending_mesh.visible = true
	pending_mesh.material_override.albedo_color = Color(str(pending.get("color", "#e39756")))
	var mesh: ImmediateMesh = pending_mesh.mesh
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var a := pending_wire.to_local(start)
	var b := pending_wire.to_local(wire_cursor)
	var sag := minf(a.distance_to(b) * 0.3, 0.2)
	var rings := []
	for index in range(25):
		var t := float(index) / 24
		var point := a.lerp(b, t) + Vector3(0, -4 * sag * t * (1 - t), 0.04)
		var tangent := (b - a + Vector3(0, -4 * sag * (1 - 2 * t), 0)).normalized()
		var reference := Vector3.FORWARD if absf(tangent.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
		var normal := tangent.cross(reference).normalized()
		var binormal := tangent.cross(normal).normalized()
		var ring := []
		for side in range(8): ring.append(point + (normal * cos(TAU * side / 8) + binormal * sin(TAU * side / 8)) * 0.0036)
		rings.append(ring)
	for index in range(24):
		for side in range(8):
			var next := (side + 1) % 8
			for pair in [Vector2i(index, side), Vector2i(index + 1, next), Vector2i(index + 1, side), Vector2i(index, side), Vector2i(index, next), Vector2i(index + 1, next)]:
				mesh.surface_add_vertex(rings[pair.x][pair.y])
	mesh.surface_end()

func _frame_rack() -> void:
	if modules.is_empty():
		return
	var bounds := Rect2()
	var first := true
	for view: CardinalModuleView in modules.values():
		var data := view.descriptor
		var rectangle := Rect2(float(data["x"]), float(data["y"]), float(data["width"]), float(data["height"]))
		bounds = rectangle if first else bounds.merge(rectangle)
		first = false
	if rack_case != null and rack_case.bounds.has_area(): bounds = rack_case.bounds
	target = Vector3(bounds.get_center().x * ModuleView.SCALE, -bounds.get_center().y * ModuleView.SCALE, 0)
	distance = maxf(bounds.size.x * ModuleView.SCALE * 1.6, bounds.size.y * ModuleView.SCALE * 2.5)
	_update_camera()

func _apply_lighting() -> void:
	if immersive_environment != null:
		immersive_environment.update_light()
		return
	var preset: Dictionary = LIGHTING_PRESETS[lighting_preset]
	environment.background_color = Color(preset["background"])
	environment.ambient_light_color = Color(preset["ambient"])
	environment.ambient_light_energy = float(preset["ambient_energy"]) * brightness
	key_light.light_color = Color(preset["key"])
	key_light.light_energy = float(preset["key_energy"]) * brightness
	fill_light.light_color = Color(preset["fill"])
	fill_light.light_energy = float(preset["fill_energy"]) * brightness

func _pan_camera(delta: Vector2) -> void:
	var units_per_pixel := 2.0 * distance * tan(deg_to_rad(camera.fov) / 2.0) / maxf(get_viewport().get_visible_rect().size.y, 1)
	target += (-camera.global_basis.x * delta.x + camera.global_basis.y * delta.y) * units_per_pixel
	_update_camera()

func _orbit_camera(delta: Vector2) -> void:
	yaw = clampf(yaw - delta.x * 0.004, -1.25, 1.25)
	pitch = clampf(pitch + delta.y * 0.004, -0.8, 0.8)
	_update_camera()

func _zoom_camera(factor: float) -> void:
	if not is_finite(factor) or factor <= 0: return
	distance = clampf(distance / factor, 0.3, 20)
	_update_camera()

func _update_camera() -> void:
	camera.position = target + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	camera.look_at(target)

func _hit(at: Vector2) -> Dictionary:
	var from := camera.project_ray_origin(at)
	var query := PhysicsRayQueryParameters3D.create(from, from + camera.project_ray_normal(at) * 100)
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return {}
	var view: CardinalModuleView = result["collider"].get_meta("module_view")
	return {"view": view, "pixel": view.pixel_at(result["position"])}

func _clear_focus() -> void:
	magnet_latched = ""
	focus_binding.clear()
	if control_focus == null: return
	control_focus.active = false
	control_focus.title_strip = false
	control_focus.queue_redraw()
	tooltip.text = ""
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)

func _title_hit(hit: Dictionary) -> bool:
	return not hit.is_empty() and hit["pixel"].y >= 0 and hit["pixel"].y <= 32

func _nearest_control(hit: Dictionary, at: Vector2) -> Dictionary:
	if hit.is_empty(): return {}
	var view: CardinalModuleView = hit["view"]
	var best := {}
	var nearest := INF
	for control: Dictionary in view.descriptor.get("controls", []):
		if not control.get("visible", true): continue
		if not str(control["kind"]) in ["knob", "slider", "switch", "button", "port", "custom"]: continue
		var pixel := Vector2(float(control["x"]), float(control["y"]))
		if control["kind"] == "slider":
			var fraction := float(control.get("normalized", 0))
			pixel = Vector2(lerpf(float(control.get("start_x", pixel.x)), float(control.get("end_x", pixel.x)), fraction), lerpf(float(control.get("start_y", pixel.y)), float(control.get("end_y", pixel.y)), fraction))
		var world := view.to_global(Vector3(pixel.x * ModuleView.SCALE, -pixel.y * ModuleView.SCALE, 0.015))
		if camera.is_position_behind(world): continue
		var screen := camera.unproject_position(world)
		var edge := camera.unproject_position(world + camera.global_basis.x * float(control["width"]) * ModuleView.SCALE / 2)
		var radius := screen.distance_to(edge)
		var separation := at.distance_to(screen)
		if separation < minf(48, maxf(20, radius + 10)) and separation < nearest:
			nearest = separation
			best = {"view": view, "pixel": pixel, "control": control, "screen": screen, "radius": radius}
	return best

func _magnetic_hit(hit: Dictionary, at: Vector2, warp: bool = false) -> Dictionary:
	_clear_focus_visual()
	if _title_hit(hit):
		magnet_latched = ""
		var view: CardinalModuleView = hit["view"]
		var start := camera.unproject_position(view.to_global(Vector3.ZERO))
		var end := camera.unproject_position(view.to_global(Vector3(float(view.descriptor["width"]) * ModuleView.SCALE, -32 * ModuleView.SCALE, 0)))
		control_focus.title_rect = Rect2(start, end - start).abs()
		control_focus.title_strip = true
		control_focus.queue_redraw()
		tooltip.text = "Drag title to move module"
		tooltip.position = at + Vector2(18, 18)
		Input.set_default_cursor_shape(Input.CURSOR_MOVE)
		return hit
	if not magnet_enabled: return hit
	var closest := _nearest_control(hit, at)
	if closest.is_empty():
		magnet_latched = ""
		return hit
	var control: Dictionary = closest["control"]
	control_focus.active = true
	control_focus.center = closest["screen"]
	control_focus.radius = maxf(float(closest["radius"]), 7)
	control_focus.queue_redraw()
	tooltip.text = _focus_text(control)
	focus_binding = {"module": str(closest["view"].descriptor["id"]), "id": str(control["id"]), "kind": control["kind"], "direction": str(control.get("direction", ""))}
	var label_at: Vector2 = closest["screen"] + Vector2(control_focus.radius + 12, -12)
	tooltip.position = Vector2(minf(label_at.x, get_viewport().get_visible_rect().size.x - tooltip.get_minimum_size().x - 16), maxf(65, label_at.y))
	var key := "%s/%s/%s/%s" % [closest["view"].descriptor["id"], control["kind"], control["id"], control.get("direction", "")]
	var entering := key != magnet_latched
	# Latch before moving the cursor: macOS may deliver another motion event.
	magnet_latched = key
	if warp and entering:
		_snap_cursor(closest["screen"])
	return closest

func _snap_cursor(position: Vector2) -> void:
	var viewport := get_viewport()
	# Camera projection uses viewport coordinates, which can differ from window
	# pixels on Retina displays and whenever the window is resized.
	if not position.is_finite() or not viewport.get_visible_rect().has_point(position):
		return
	if not get_window().has_focus() or dragging or moving or orbiting or panning:
		return
	viewport.warp_mouse(position)

func _clear_focus_visual() -> void:
	focus_binding.clear()
	control_focus.active = false
	control_focus.title_strip = false
	control_focus.queue_redraw()
	tooltip.text = ""
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)

func _focus_text(control: Dictionary) -> String:
	return "%s%s" % [str(control.get("label", control["kind"])).capitalize(), " · " + str(control["display"]) if control.has("display") else ""]

func _mods(event: InputEventWithModifiers) -> int:
	return (1 if event.shift_pressed else 0) | (2 if event.ctrl_pressed else 0) | (4 if event.alt_pressed else 0) | (8 if event.meta_pressed else 0)

func _release() -> void:
	if bridge != null and (dragging or moving):
		bridge.send_command("release")
	dragging = false
	moving = false
	captured_module = ""
	_pending_wire()

func _unhandled_input(event: InputEvent) -> void:
	if xr_session != null and xr_session.active: return
	if module_browser != null and module_browser.visible: return
	if overlay_mode == "menu":
		if event is InputEventMouseButton and event.pressed:
			bridge.send_command("escape")
			overlay.visible = false
			return
		if event is InputEventKey:
			_overlay_input(event)
		return
	if event is InputEventMagnifyGesture:
		_clear_focus()
		if not dragging and not moving: _zoom_camera(event.factor)
		return
	if event is InputEventPanGesture:
		_clear_focus()
		if not dragging and not moving:
			if event.shift_pressed: _orbit_camera(event.delta * 12.0)
			else: _pan_camera(event.delta * 12.0)
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if not event.pressed and navigation_drag:
				navigation_drag = false
				orbiting = false
				panning = false
				return
			if event.pressed and (view_mode != 0 or Input.is_physical_key_pressed(KEY_SPACE)):
				_release()
				_clear_focus()
				navigation_drag = true
				panning = event.shift_pressed if Input.is_physical_key_pressed(KEY_SPACE) else view_mode == 2
				orbiting = not panning
				return
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			orbiting = event.pressed and not event.shift_pressed
			panning = event.pressed and event.shift_pressed
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed: _zoom_camera(pow(1.1, maxf(event.factor, 0.1) * (1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1)))
			return
		if not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if moving:
				bridge.send_command("move_end")
			elif dragging:
				var hit := _hit(event.position)
				if not hit.is_empty():
					_send_pointer(hit, "up", event)
				else:
					bridge.send_command("release")
			moving = false
			dragging = false
			captured_module = ""
			_pending_wire()
			return
		var hit := _hit(event.position)
		if hit.is_empty():
			_clear_focus()
			return
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT and _title_hit(hit):
			_clear_focus()
			captured_module = str(hit["view"].descriptor["id"])
			moving = true
			bridge.send_command("move_begin", {"module": captured_module})
		elif event.pressed:
			hit = _magnetic_hit(hit, event.position)
			captured_module = str(hit["view"].descriptor["id"])
			dragging = event.button_index == MOUSE_BUTTON_LEFT
			_send_pointer(hit, "down", event)
		else:
			_send_pointer(hit, "up", event)
	elif event is InputEventMouseMotion:
		if orbiting:
			_orbit_camera(event.relative)
		elif panning:
			_pan_camera(event.relative)
		elif moving:
			bridge.send_command("move_delta", {"dx": event.relative.x / ModuleView.SCALE * distance * 0.001, "dy": event.relative.y / ModuleView.SCALE * distance * 0.001})
		else:
			if view_mode != 0 or Input.is_physical_key_pressed(KEY_SPACE):
				_clear_focus()
				return
			var hit := _hit(event.position)
			if not dragging:
				hit = _magnetic_hit(hit, event.position, true)
			if not hit.is_empty():
				_send_pointer(hit, "motion", event)
			elif dragging:
				bridge.send_command("drag_delta", {"dx": event.relative.x, "dy": event.relative.y, "mods": _mods(event)})
				var ray_origin := camera.project_ray_origin(event.position)
				var ray_direction := camera.project_ray_normal(event.position)
				if absf(ray_direction.z) > 0.001:
					wire_cursor = ray_origin + ray_direction * ((0.026 - ray_origin.z) / ray_direction.z)
					_pending_wire()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_release()
			overlay.visible = false
			bridge.send_command("escape")
		elif event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE:
			var hit := _hit(get_viewport().get_mouse_position())
			if not hit.is_empty():
				bridge.send_command("remove", {"module": str(hit["view"].descriptor["id"])})

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and settings_panel.visible:
		if not settings_panel.get_global_rect().has_point(event.position) and not settings_button.get_global_rect().has_point(event.position):
			settings_panel.hide()
	if event is InputEventMouseMotion and get_viewport().gui_get_hovered_control() != null:
		_clear_focus()
	# GUI controls consume releases before _unhandled_input receives them.
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if get_viewport().gui_get_hovered_control() != null:
			if dragging or moving: _release()
			navigation_drag = false
			orbiting = false
			panning = false

func _send_pointer(hit: Dictionary, phase: String, event: InputEventWithModifiers) -> void:
	if phase == "down" and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		menu_anchor = event.position
		menu_surface_started = false
	var pixel: Vector2 = hit["pixel"]
	wire_cursor = hit["view"].to_global(Vector3(pixel.x * ModuleView.SCALE, -pixel.y * ModuleView.SCALE, 0.026))
	_pending_wire()
	bridge.send_command("pointer", {"module": str(hit["view"].descriptor["id"]), "x": pixel.x, "y": pixel.y, "phase": phase, "button": 1 if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT else 0, "mods": _mods(event)})
	if phase == "down" and event is InputEventMouseButton and event.double_click:
		bridge.send_command("reset_hovered")

func _overlay_input(event: InputEvent) -> void:
	if overlay_texture == null:
		return
	if event is InputEventPanGesture:
		var image_size := Vector2(overlay_texture.get_width(), overlay_texture.get_height())
		var scale_factor := minf(overlay.size.x / image_size.x, overlay.size.y / image_size.y)
		var pixel: Vector2 = (event.position - (overlay.size - image_size * scale_factor) / 2) / scale_factor + overlay_origin
		bridge.send_command("pointer", {"module": "scene", "x": pixel.x, "y": pixel.y, "phase": "motion", "mods": _mods(event)})
		bridge.send_command("scroll", {"dx": -event.delta.x, "dy": -event.delta.y})
		overlay.accept_event()
		return
	if event is InputEventMagnifyGesture:
		overlay.accept_event()
		return
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		var image_size := Vector2(overlay_texture.get_width(), overlay_texture.get_height())
		var scale_factor := minf(overlay.size.x / image_size.x, overlay.size.y / image_size.y)
		var offset := (overlay.size - image_size * scale_factor) / 2
		var pixel: Vector2 = (event.position - offset) / scale_factor + overlay_origin
		if event is InputEventMouseButton and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			bridge.send_command("pointer", {"module": "scene", "x": pixel.x, "y": pixel.y, "phase": "motion", "mods": _mods(event)})
			bridge.send_command("scroll", {"dx": 0, "dy": 1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1})
			overlay.accept_event()
			return
		var phase := "motion"
		if event is InputEventMouseButton:
			phase = "down" if event.pressed else "up"
		bridge.send_command("pointer", {"module": "scene", "x": pixel.x, "y": pixel.y, "phase": phase, "button": 1 if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT else 0, "mods": _mods(event)})
		if event is InputEventMouseButton and event.pressed:
			overlay.grab_focus()
		overlay.accept_event()
	elif event is InputEventKey:
		if event.pressed and event.keycode == KEY_ESCAPE:
			_release()
			overlay.visible = false
			bridge.send_command("escape")
			overlay.accept_event()
			return
		var key_map := {KEY_ESCAPE: 256, KEY_ENTER: 257, KEY_TAB: 258, KEY_BACKSPACE: 259, KEY_INSERT: 260, KEY_DELETE: 261, KEY_RIGHT: 262, KEY_LEFT: 263, KEY_DOWN: 264, KEY_UP: 265, KEY_HOME: 268, KEY_END: 269}
		bridge.send_command("key", {"key": key_map.get(event.keycode, event.keycode), "pressed": int(event.pressed), "mods": _mods(event)})
		if event.pressed and event.unicode > 0 and not event.ctrl_pressed and not event.meta_pressed:
			bridge.send_command("text", {"codepoint": event.unicode})
		overlay.accept_event()

func _process(delta: float) -> void:
	if OS.get_environment("CARDINAL_3D_DIAGNOSTICS") == "1":
		var now := Time.get_ticks_usec()
		var frame_seconds := float(now - performance_previous_usec) / 1000000.0 if performance_previous_usec > 0 else 0.0
		performance_previous_usec = now
		performance_elapsed += frame_seconds
		performance_frames += 1
		performance_worst = maxf(performance_worst, frame_seconds)
		if performance_elapsed >= 5:
			print("VR timing: %.1f fps, worst %.1f ms, process %.1f ms, physics %.1f ms, draw calls %d" % [performance_frames / performance_elapsed, performance_worst * 1000, Performance.get_monitor(Performance.TIME_PROCESS) * 1000, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
			var diagnostics := FileAccess.open(ProjectSettings.globalize_path("res://../vr-timing.json"), FileAccess.WRITE)
			if diagnostics != null:
				diagnostics.store_string(JSON.stringify({"fps": performance_frames / performance_elapsed, "worst_frame_ms": performance_worst * 1000, "process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000, "physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000, "draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), "modules": modules.size(), "xr_focused": xr_session != null and xr_session.was_focused, "snapshot_hz": bridge.snapshot_count / performance_elapsed, "incoming_bytes": bridge.incoming.size(), "outgoing_bytes": bridge.outgoing.size() }))
			bridge.snapshot_count = 0
			performance_elapsed = 0
			performance_frames = 0
			performance_worst = 0
	status_timer = maxf(status_timer - delta, 0)
	if bridge.connected and status_timer == 0 and not snapshot.is_empty():
		status_label.text = "  %d modules · %d cables · %d fps · Cardinal owns audio and patch state" % [modules.size(), snapshot.get("cables", []).size(), Engine.get_frames_per_second()]
