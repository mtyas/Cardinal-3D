extends PanelContainer

signal insert_requested(plugin: String, model: String)

const ModuleView := preload("res://scripts/module_view.gd")
const Hardware := preload("res://scripts/hardware.gd")
const COLUMNS := 4
const ROW_HEIGHT := 0.60
const SCROLL_ROW := 100.0
const WINDOW_ROWS := 4
var bridge: CardinalBridgeClient
var catalog: Array = []
var filtered: Array = []
var first_index := 0
var last_index := 0
var window_key := ""
var scrollbar: VScrollBar
var preview_cache: Dictionary = {}
var viewport: SubViewport
var camera: Camera3D
var gallery: Node3D
var search: LineEdit
var sort_picker: OptionButton
var type_picker: OptionButton
var manufacturer_picker: OptionButton
var category_button: Button
var manufacturer_button: Button
var filter_panel: PanelContainer
var filter_grid: GridContainer
var filter_label: Label
var filter_previous: Button
var filter_next: Button
var filter_picker: OptionButton
var filter_page := 0
var filter_scroll_elapsed := 0.35
const FILTER_PAGE_SIZE := 20
var count: Label
var selection: Label
var add_button: Button
var previews: Dictionary = {}
var selected := ""
var pressed_at := Vector2.ZERO
var rotating := false

func setup(client: CardinalBridgeClient) -> void:
	bridge = client
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	offset_left = 32; offset_right = -32; offset_top = 65; offset_bottom = -40
	var style := StyleBoxFlat.new()
	style.bg_color = Color("111a23")
	style.set_content_margin_all(16)
	style.set_corner_radius_all(12)
	add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := Label.new()
	title.text = "Modules"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color("62e4ca"))
	header.add_child(title)
	search = LineEdit.new()
	search.placeholder_text = "Search modules or plugin…"
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.text_changed.connect(func(_text: String): _filter(); _reset_scroll())
	header.add_child(search)
	manufacturer_picker = OptionButton.new()
	manufacturer_picker.add_item("All manufacturers")
	manufacturer_picker.tooltip_text = "Show one manufacturer"
	manufacturer_picker.item_selected.connect(func(_index: int): _filter(); _reset_scroll())
	header.add_child(manufacturer_picker)
	manufacturer_picker.hide()
	manufacturer_button = Button.new()
	manufacturer_button.custom_minimum_size = Vector2(240, 56)
	manufacturer_button.add_theme_font_size_override("font_size", 20)
	manufacturer_button.pressed.connect(func(): _show_filter_choices(manufacturer_picker))
	header.add_child(manufacturer_button)
	type_picker = OptionButton.new()
	type_picker.custom_minimum_size.x = 150
	type_picker.add_item("All types")
	type_picker.item_selected.connect(func(_index: int): _filter(); _reset_scroll())
	header.add_child(type_picker)
	type_picker.hide()
	category_button = Button.new()
	category_button.custom_minimum_size = Vector2(220, 56)
	category_button.add_theme_font_size_override("font_size", 20)
	category_button.pressed.connect(func(): _show_filter_choices(type_picker))
	header.add_child(category_button)
	sort_picker = OptionButton.new()
	for label in ["Sort: Name", "Sort: Manufacturer", "Sort: Module type"]: sort_picker.add_item(label)
	sort_picker.tooltip_text = "Order modules by"
	sort_picker.item_selected.connect(func(_index: int): _filter(); _reset_scroll())
	header.add_child(sort_picker)
	var close := preload("res://scripts/ui_theme.gd").close_button(close_browser)
	header.add_child(close)
	filter_panel = PanelContainer.new()
	column.add_child(filter_panel)
	var filter_column := VBoxContainer.new()
	filter_panel.add_child(filter_column)
	var navigation := HBoxContainer.new()
	filter_column.add_child(navigation)
	filter_previous = Button.new(); filter_previous.text = "Previous"
	filter_previous.custom_minimum_size = Vector2(140, 48)
	filter_previous.pressed.connect(func(): _filter_page_by(-1))
	navigation.add_child(filter_previous)
	filter_label = Label.new(); filter_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filter_label.add_theme_font_size_override("font_size", 20)
	navigation.add_child(filter_label)
	filter_next = Button.new(); filter_next.text = "Next"
	filter_next.custom_minimum_size = Vector2(140, 48)
	filter_next.pressed.connect(func(): _filter_page_by(1))
	navigation.add_child(filter_next)
	var dismiss := preload("res://scripts/ui_theme.gd").close_button(func(): filter_panel.hide())
	navigation.add_child(dismiss)
	filter_grid = GridContainer.new(); filter_grid.columns = 4
	filter_column.add_child(filter_grid)
	filter_panel.hide()
	var shelf := HBoxContainer.new()
	shelf.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(shelf)
	var container := SubViewportContainer.new()
	container.stretch = true
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shelf.add_child(container)
	scrollbar = VScrollBar.new()
	scrollbar.custom_minimum_size.x = 16
	scrollbar.step = 1.0
	scrollbar.value_changed.connect(_scroll_changed)
	shelf.add_child(scrollbar)
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	container.add_child(viewport)
	container.gui_input.connect(_gallery_input)
	gallery = Node3D.new()
	viewport.add_child(gallery)
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("17232f")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("bdccda")
	environment.ambient_light_energy = 0.85
	var sky := Sky.new(); sky.sky_material = ProceduralSkyMaterial.new()
	environment.sky = sky
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	world.environment = environment
	viewport.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-20, -25, 0)
	light.light_energy = 1.4
	viewport.add_child(light)
	camera = Camera3D.new()
	camera.position = Vector3(0, 0.04, 2.0)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.15
	viewport.add_child(camera)
	var footer := HBoxContainer.new()
	column.add_child(footer)
	selection = Label.new(); selection.text = "Select a module"
	selection.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(selection)
	count = Label.new(); footer.add_child(count)
	add_button = Button.new(); add_button.text = "Add selected module"; add_button.disabled = true
	add_button.theme_type_variation = "PrimaryButton"
	add_button.icon = preload("res://scripts/ui_theme.gd").icon("modules")
	add_button.add_theme_constant_override("icon_max_width", 28)
	add_button.pressed.connect(_insert)
	footer.add_child(add_button)
	var hint := Label.new()
	hint.text = "Stick up/down to scroll · Click to select · Drag to rotate · Add selected module · Escape to close"
	hint.add_theme_font_size_override("font_size", 18)
	column.add_child(hint)
	visible = false

func set_catalog(models: Array) -> void:
	catalog = models
	var types: Array[String] = []
	var manufacturers: Array[String] = []
	var previous_maker := manufacturer_picker.get_item_text(manufacturer_picker.selected) if manufacturer_picker.selected > 0 else ""
	var previous_type := type_picker.get_item_text(type_picker.selected) if type_picker.selected > 0 else ""
	for model: Dictionary in models:
		var maker := str(model.get("manufacturer", model["plugin"]))
		if maker not in manufacturers: manufacturers.append(maker)
		for tag in model.get("tags", []):
			if str(tag) not in types: types.append(str(tag))
	types.sort()
	manufacturers.sort()
	manufacturer_picker.clear()
	manufacturer_picker.add_item("All manufacturers")
	for maker in manufacturers:
		manufacturer_picker.add_item(maker)
		if maker == previous_maker: manufacturer_picker.select(manufacturer_picker.item_count - 1)
	type_picker.clear()
	type_picker.add_item("All types")
	for tag in types:
		type_picker.add_item(tag)
		if tag == previous_type: type_picker.select(type_picker.item_count - 1)
	if visible:
		_filter()
		_reset_scroll()

func show_browser() -> void:
	visible = true
	filter_panel.hide()
	_filter()
	_reset_scroll()
	search.grab_focus()

func close_browser() -> void:
	visible = false
	rotating = false
	bridge.send_command("preview_clear")
	_clear_gallery()

func _filter() -> void:
	category_button.text = type_picker.get_item_text(maxi(type_picker.selected, 0))
	manufacturer_button.text = manufacturer_picker.get_item_text(maxi(manufacturer_picker.selected, 0))
	filtered.clear()
	var query := search.text.to_lower()
	var type_filter := "" if type_picker.selected <= 0 else type_picker.get_item_text(type_picker.selected)
	var manufacturer_filter := "" if manufacturer_picker.selected <= 0 else manufacturer_picker.get_item_text(manufacturer_picker.selected)
	for model: Dictionary in catalog:
		var tags: Array = model.get("tags", [])
		var text := str(model["plugin"]) + " " + str(model["model"]) + " " + str(model["name"]) + " " + str(model.get("manufacturer", "")) + " " + " ".join(tags)
		var maker := str(model.get("manufacturer", model["plugin"]))
		if (manufacturer_filter.is_empty() or maker == manufacturer_filter) and (type_filter.is_empty() or type_filter in tags) and (query.is_empty() or query in text.to_lower()):
			filtered.append(model)
	filtered.sort_custom(func(a: Dictionary, b: Dictionary): return _sort_key(a) < _sort_key(b))

func _show_filter_choices(picker: OptionButton) -> void:
	filter_picker = picker
	filter_page = maxi(picker.selected, 0) / FILTER_PAGE_SIZE
	filter_panel.show()
	_render_filter_choices()

func _filter_page_by(amount: int) -> void:
	filter_page = clampi(filter_page + amount, 0, maxi(0, ceili(float(filter_picker.item_count) / FILTER_PAGE_SIZE) - 1))
	_render_filter_choices()

func _render_filter_choices() -> void:
	for child in filter_grid.get_children():
		filter_grid.remove_child(child)
		child.queue_free()
	var pages := maxi(1, ceili(float(filter_picker.item_count) / FILTER_PAGE_SIZE))
	filter_label.text = "%s — page %d / %d" % ["Categories" if filter_picker == type_picker else "Manufacturers", filter_page + 1, pages]
	filter_previous.disabled = filter_page == 0
	filter_next.disabled = filter_page == pages - 1
	for index in range(filter_page * FILTER_PAGE_SIZE, mini((filter_page + 1) * FILTER_PAGE_SIZE, filter_picker.item_count)):
		var button := Button.new()
		button.text = filter_picker.get_item_text(index)
		button.custom_minimum_size = Vector2(280, 56)
		button.add_theme_font_size_override("font_size", 20)
		button.toggle_mode = true
		button.button_pressed = index == filter_picker.selected
		button.pressed.connect(func(): _choose_filter(index))
		filter_grid.add_child(button)

func _choose_filter(index: int) -> void:
	filter_picker.select(index)
	filter_panel.hide()
	_filter()
	_reset_scroll()

func scroll_vr(axis: float, delta: float) -> void:
	if absf(axis) <= 0.18:
		filter_scroll_elapsed = 0.35
		return
	if filter_panel.visible:
		filter_scroll_elapsed += delta
		if filter_scroll_elapsed >= 0.35:
			_filter_page_by(-1 if axis > 0 else 1)
			filter_scroll_elapsed = 0
		return
	var amount := signf(axis) * (absf(axis) - 0.18) / 0.82
	scrollbar.value = clampf(scrollbar.value - amount * 240.0 * delta, 0, maxf(0, scrollbar.max_value - scrollbar.page))

func _sort_key(model: Dictionary) -> String:
	var name := str(model.get("module_name", model["name"])).to_lower()
	var maker := str(model.get("manufacturer", model["plugin"])).to_lower()
	var types: Array = model.get("tags", []).duplicate()
	types.sort()
	var category := str(types[0]).to_lower() if not types.is_empty() else "zz uncategorized"
	var identity := str(model["plugin"]) + "/" + str(model["model"])
	match sort_picker.selected:
		1: return maker + "/" + name + "/" + identity
		2: return category + "/" + name + "/" + maker + "/" + identity
	return name + "/" + maker + "/" + identity

func _clear_gallery() -> void:
	for child in gallery.get_children():
		gallery.remove_child(child); child.queue_free()
	previews.clear()
	selected = ""
	add_button.disabled = true
	selection.text = "Select a module"

func _reset_scroll() -> void:
	_clear_gallery()
	window_key = "reset"
	scrollbar.set_value_no_signal(0)
	scrollbar.page = camera.size / ROW_HEIGHT * SCROLL_ROW
	scrollbar.max_value = maxf(scrollbar.page, ceilf(float(filtered.size()) / COLUMNS) * SCROLL_ROW)
	scrollbar.visible = scrollbar.max_value > scrollbar.page
	_scroll_changed(0)

func _scroll_changed(value: float) -> void:
	rotating = false
	camera.position.y = 0.04 - value / SCROLL_ROW * ROW_HEIGHT
	_refresh_window()

func _refresh_window() -> void:
	first_index = maxi(0, int(floor(scrollbar.value / SCROLL_ROW)) - 1) * COLUMNS
	last_index = mini(first_index + WINDOW_ROWS * COLUMNS, filtered.size())
	var ids: Array[String] = []
	for index in range(first_index, last_index):
		ids.append("preview/%s/%s" % [filtered[index]["plugin"], filtered[index]["model"]])
	var key := "|".join(ids)
	count.text = "%d modules" % filtered.size()
	if filtered.is_empty(): selection.text = "No matching modules"
	if key == window_key: return
	window_key = key
	for id in previews.keys():
		if id not in ids:
			previews[id]["pivot"].queue_free()
			previews[id]["label"].queue_free()
			previews[id]["highlight"].queue_free()
			previews.erase(id)
	if not previews.has(selected):
		selected = ""
		add_button.disabled = true
		if not filtered.is_empty(): selection.text = "Select a module"
	bridge.send_command("preview_clear")
	for index in range(first_index, last_index):
		var model: Dictionary = filtered[index]
		var id := "preview/%s/%s" % [model["plugin"], model["model"]]
		if not previews.has(id) and preview_cache.has(id):
			receive_descriptor(preview_cache[id]["data"])
			if preview_cache[id].has("image"): receive_surface(id, preview_cache[id]["image"])
		bridge.send_command("preview", {"plugin": model["plugin"], "model": model["model"]})

func receive_descriptor(data: Dictionary) -> void:
	if not visible: return
	var slot := -1
	for index in range(first_index, last_index):
		if data["plugin"] == filtered[index]["plugin"] and data["model"] == filtered[index]["model"]:
			slot = index
	if slot < 0: return
	var id := str(data["id"])
	if previews.has(id): return
	var pivot := Node3D.new()
	pivot.position = Vector3((slot % COLUMNS - 1.5) * 0.46, 0.24 - floorf(float(slot) / COLUMNS) * ROW_HEIGHT, 0)
	pivot.rotation.y = -0.16
	gallery.add_child(pivot)
	var view := ModuleView.new()
	pivot.add_child(view)
	var descriptor := data.duplicate(true)
	descriptor["x"] = 0; descriptor["y"] = 0
	view.setup(descriptor)
	var width := float(data["width"]) * ModuleView.SCALE
	var height := float(data["height"]) * ModuleView.SCALE
	pivot.scale = Vector3.ONE * minf(0.42 / width, 0.40 / height)
	view.position = Vector3(-width / 2, height / 2, 0)
	var label := Label3D.new()
	preload("res://scripts/clear_text.gd").apply(label)
	var metadata: Dictionary = filtered[slot]
	label.text = str(metadata.get("module_name", metadata.get("name", data["model"]))) + "\n" + str(metadata.get("manufacturer", data["plugin"]))
	label.font_size = 20
	label.width = 280
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.pixel_size = 0.0014
	label.position = Vector3(pivot.position.x, pivot.position.y + 0.255, 0.035)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	gallery.add_child(label)
	var highlight := MeshInstance3D.new()
	var card := QuadMesh.new()
	card.size = Vector2(0.445, 0.48)
	highlight.mesh = card
	var highlight_material := StandardMaterial3D.new()
	highlight_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	highlight_material.albedo_color = Color("167c96")
	highlight.material_override = highlight_material
	highlight.position = Vector3(pivot.position.x, pivot.position.y, -0.08)
	highlight.visible = false
	gallery.add_child(highlight)
	previews[id] = {"view": view, "pivot": pivot, "data": data, "label": label, "highlight": highlight, "title": label.text}
	if preview_cache.size() >= 64 and not preview_cache.has(id): preview_cache.clear()
	if not preview_cache.has(id): preview_cache[id] = {}
	preview_cache[id]["data"] = data

func receive_surface(id: String, image: Image) -> void:
	if previews.has(id):
		previews[id]["view"].apply_surface(image)
		if preview_cache.has(id): preview_cache[id]["image"] = image

func _pick(at: Vector2) -> String:
	var from := camera.project_ray_origin(at)
	var query := PhysicsRayQueryParameters3D.create(from, from + camera.project_ray_normal(at) * 10)
	var hit := gallery.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return ""
	return str(hit["collider"].get_meta("module_view").descriptor["id"])

func _gallery_input(event: InputEvent) -> void:
	if event is InputEventPanGesture:
		scrollbar.value += event.delta.y * 8.0
		accept_event()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		scrollbar.value += (30.0 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -30.0) * event.factor
		accept_event()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		rotating = event.pressed
		if event.pressed:
			pressed_at = event.position
			var id := _pick(event.position)
			if id.is_empty(): return
			selected = id
			for key in previews:
				previews[key]["label"].modulate = Color("6ae1ff") if key == selected else Color.WHITE
				previews[key]["highlight"].visible = key == selected
				previews[key]["label"].text = previews[key]["title"]
			selection.text = str(previews[id]["data"]["name"]) + " · " + str(previews[id]["data"]["plugin"])
			add_button.text = "Add " + str(previews[id]["data"].get("name", previews[id]["data"]["model"]))
			add_button.disabled = false
			if event.double_click: _insert()
	elif event is InputEventMouseMotion and rotating and previews.has(selected):
		var pivot: Node3D = previews[selected]["pivot"]
		pivot.rotation.y = clampf(pivot.rotation.y + event.relative.x * 0.009, -0.8, 0.8)
		pivot.rotation.x = clampf(pivot.rotation.x + event.relative.y * 0.006, -0.4, 0.4)

func _insert() -> void:
	if not previews.has(selected): return
	var data: Dictionary = previews[selected]["data"]
	var plugin := str(data["plugin"])
	var model := str(data["model"])
	close_browser()
	insert_requested.emit(plugin, model)

func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close_browser()
		get_viewport().set_input_as_handled()
