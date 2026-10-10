extends SceneTree

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
	for child in view.toolbar.get_children():
		check(not child is OptionButton, "Top bar must use the browser as its only module picker")
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../build/audible-library.json"))
	var catalog: Array = []
	for item: Dictionary in report["modules"]:
		catalog.append({"plugin": item["plugin"], "model": item["model"], "name": item["descriptor"]["name"]})
	var browser = view.module_browser
	browser.set_catalog(catalog)
	browser.show_browser()
	check(browser.filtered.size() == catalog.size() and browser.scrollbar.visible, "Browser must scroll the expanded catalog")
	var scroll := InputEventPanGesture.new(); scroll.delta = Vector2(0, 20)
	browser._gallery_input(scroll)
	check(browser.scrollbar.value > 0 and browser.camera.position.y < -0.10, "Trackpad scrolling must move the gallery camera")
	check(browser.last_index - browser.first_index <= 16, "Scrollable browser must bound its live preview window")
	browser.scrollbar.value = browser.scrollbar.max_value
	check(browser.last_index == catalog.size(), "Scroll must reach the final catalog modules")
	browser.search.text = "no-module-matches-this-query"
	browser._filter(); browser._reset_scroll()
	check(browser.filtered.is_empty() and browser.previews.is_empty() and browser.add_button.disabled, "Empty search must clear previews and disable insertion")
	browser.search.text = "Plaits"
	browser._filter(); browser._clear_gallery(); browser._reset_scroll()
	check(browser.filtered.size() == 1 and browser.filtered[0]["model"] == "Plaits", "Search must match model slug")
	var descriptor: Dictionary
	for item: Dictionary in report["modules"]:
		if item["model"] == "Plaits": descriptor = item["descriptor"].duplicate(true)
	descriptor["id"] = "preview/AudibleInstruments/Plaits"
	browser.receive_descriptor(descriptor)
	await physics_frame
	await physics_frame
	var entry: Dictionary = browser.previews[descriptor["id"]]
	var module = entry["view"]
	var center: Vector3 = module.to_global(Vector3(float(descriptor["width"]) * 0.001, -float(descriptor["height"]) * 0.001, 0))
	var screen: Vector2 = browser.camera.unproject_position(center)
	check(browser._pick(screen) == descriptor["id"], "3D preview must be selectable by ray hit")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT; click.pressed = true; click.position = screen
	browser._gallery_input(click)
	check(browser.selected == descriptor["id"] and not browser.add_button.disabled, "Click must select a preview")
	check(entry.highlight.visible and "SELECTED" in entry.label.text and descriptor.name in browser.add_button.text, "The selected module must have a visible card, label and named Add button")
	var rotation: float = entry["pivot"].rotation.y
	var motion := InputEventMouseMotion.new(); motion.relative = Vector2(20, 0)
	browser._gallery_input(motion)
	check(entry["pivot"].rotation.y != rotation, "Dragging a preview must rotate it")
	var inserted: Array = []
	browser.insert_requested.connect(func(plugin: String, model: String): inserted.append([plugin, model]))
	browser._insert()
	check(inserted == [["AudibleInstruments", "Plaits"]] and not browser.visible, "Insert must bind exact plugin/model and close browser")
	check(view.modules.is_empty(), "Preview selection must not create a frontend-owned playing module")
	browser.search.text = ""
	browser.set_catalog([
		{"plugin": "Z", "model": "b", "name": "Z / Beta", "module_name": "Beta", "manufacturer": "Zulu", "tags": ["Oscillator", "Synth voice"]},
		{"plugin": "A", "model": "c", "name": "A / Charlie", "module_name": "Charlie", "manufacturer": "Alpha", "tags": ["Filter"]},
		{"plugin": "Z", "model": "a", "name": "Z / Alpha", "module_name": "Alpha", "manufacturer": "Zulu", "tags": ["Envelope"]}])
	browser.show_browser()
	check(browser.filtered[0]["model"] == "a" and browser.filtered[2]["model"] == "c", "Name ordering must ignore manufacturer prefixes")
	browser.sort_picker.select(1); browser._filter(); browser._reset_scroll()
	check(browser.filtered[0]["model"] == "c", "Manufacturer ordering must use the native brand")
	browser.sort_picker.select(2); browser._filter(); browser._reset_scroll()
	check(browser.filtered[0]["model"] == "a" and browser.filtered[1]["model"] == "c", "Module type ordering must use official tags")
	for index in range(browser.type_picker.item_count):
		if browser.type_picker.get_item_text(index) == "Synth voice": browser.type_picker.select(index)
	browser._filter(); browser._reset_scroll()
	check(browser.filtered.size() == 1 and browser.filtered[0]["model"] == "b", "Type filter must match secondary tags as well")
	for index in range(browser.manufacturer_picker.item_count):
		if browser.manufacturer_picker.get_item_text(index) == "Zulu": browser.manufacturer_picker.select(index)
	browser._filter(); browser._reset_scroll()
	check(browser.filtered.size() == 1 and browser.filtered[0]["model"] == "b", "Manufacturer and type filters must combine")
	for index in range(browser.manufacturer_picker.item_count):
		if browser.manufacturer_picker.get_item_text(index) == "Alpha": browser.manufacturer_picker.select(index)
	browser._filter(); browser._reset_scroll()
	check(browser.filtered.is_empty() and browser.add_button.disabled, "A filter intersection with no results must disable insertion")
	browser.type_picker.select(0); browser._filter(); browser._reset_scroll()
	check(browser.filtered.size() == 1 and browser.filtered[0]["model"] == "c", "Manufacturer filter alone must exclude other manufacturers")
	browser.set_catalog(browser.catalog.duplicate(true))
	check(browser.manufacturer_picker.get_item_text(browser.manufacturer_picker.selected) == "Alpha", "Catalog refresh must retain a valid manufacturer selection")
	browser.manufacturer_picker.select(0); browser._filter(); browser._reset_scroll()
	check(browser.filtered.size() == 3, "All manufacturers and all types must restore the full catalog")
	browser.close_browser()
	print("3D browser scrolling, search, picking, rotation and insertion: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
