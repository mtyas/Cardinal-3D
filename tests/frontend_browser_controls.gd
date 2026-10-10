extends SceneTree
var failures := 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var view = load("res://scripts/main.gd").new()
	root.add_child(view)
	await process_frame
	view.bridge.set_process(false)
	var browser = view.module_browser
	var models := []
	for index in range(45):
		models.append({"plugin": "Test", "model": str(index), "name": "Module %02d" % index, "manufacturer": "Maker", "tags": ["Category %02d" % index]})
	browser.set_catalog(models)
	browser.show_browser()
	await process_frame
	check(browser.category_button.custom_minimum_size.y >= 56, "Category entry must be a large target")
	browser.category_button.pressed.emit()
	check(browser.filter_panel.visible and browser.filter_grid.get_child_count() == 20, "Category chooser must show a bounded grid of large choices")
	browser._filter_page_by(1)
	var button: Button = browser.filter_grid.get_child(3)
	var label := button.text
	button.pressed.emit()
	check(not browser.filter_panel.visible and browser.category_button.text == label and browser.filtered.size() == 1, "Category click must select the exact displayed choice, update its label, and close the chooser")
	browser.type_picker.select(0)
	browser._filter(); browser._reset_scroll()
	browser.scroll_vr(-1, 0.5)
	check(browser.scrollbar.value > 0, "Stick down must scroll forward through modules")
	var value: float = browser.scrollbar.value
	browser.scroll_vr(0.1, 1)
	check(browser.scrollbar.value == value, "Stick deadzone must prevent browser drift")
	browser.scroll_vr(1, 0.5)
	check(browser.scrollbar.value < value, "Stick up must scroll toward earlier modules")
	browser._show_filter_choices(browser.type_picker)
	browser.scroll_vr(-1, 0.5)
	check(browser.filter_page == 1, "Stick down must page through categories while the chooser is open")
	browser.filter_panel.hide()
	var xr = load("res://scripts/xr_session.gd").new()
	view.add_child(xr)
	xr.host = view
	xr.origin = XROrigin3D.new(); xr.add_child(xr.origin)
	xr._move_player(Vector2(0, -1), 0, 0.5)
	check(xr.origin.position == Vector3.ZERO and browser.scrollbar.value > 0, "An open browser must consume stick scrolling without moving the rack")
	print("Browser category targets and joystick scrolling: %s" % ("PASS" if failures == 0 else "FAIL"))
	view.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
