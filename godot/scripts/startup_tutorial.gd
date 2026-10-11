extends PanelContainer
const PAGES := [
	["Welcome to Cardinal 3D", "Point a controller’s ray at a control. Use the trigger to click or hold.\n\nYou can skip this guide now and open it again from the B menu."],
	["Knobs & faders", "Point at a knob or fader and hold the trigger. Twist your wrist to adjust it; set your preferred wrist speed in the B menu.\n\nKeep the trigger held and squeeze the grip for ten times finer wrist adjustment. Let go of the grip to return to normal speed. Distance movement never changes the value."],
	["Browse & menus", "A opens the module browser. Use the joystick to scroll, click a module, then choose Add.\n\nB always opens the main menu. Select a module by its top strip, then hold grip and press B for its context menu. Use the × in a window’s top-right corner to close it."],
	["Move your viewpoint", "The joystick pans left/right and moves closer/farther.\n\nHold the grip: up/down raises or lowers you; left/right turns your view. In menus, the joystick scrolls instead."],
	["Modules & cables", "Hold a module’s top strip to show its placement ghost. Release to place it.\n\nHold an output socket and release on an input to connect a cable. Grab an input plug, pull it clear, and release away from sockets to unplug it."],
	["Arrange your racks", "Open B → Rack management and enable Layout mode. Add creates a case beside the selected rack.\n\nHold a case edge and aim the pointer to place it, including up/down. The stick pushes/pulls it along your ray. Twist your wrist to turn the case upright. Switch Layout mode off before performing."],
	["Places, devices & saving", "Environment & graphics chooses your surroundings and time of day. Audio & MIDI devices has its own menu.\n\nUse Open patch and Save patch as in the main menu. Keep the .3d.json file beside the patch to retain the case arrangement."]
]
var session
var page := 0
var heading: Label
var body: Label
var progress: Label
var picture: Control
var steps: ProgressBar
var previous: Button
var next: Button
var remember: CheckButton
var config := ConfigFile.new()
var path := ""
func setup(owner_session) -> void:
	session = owner_session
	position = Vector2(410, 95)
	custom_minimum_size = Vector2(620, 0)
	theme = preload("res://scripts/ui_theme.gd").make()
	var directory := OS.get_environment("CARDINAL_EMBEDDED_USER_DIR")
	path = directory.path_join("tutorial.cfg") if not directory.is_empty() else "user://tutorial.cfg"
	config.load(path)
	var column := VBoxContainer.new()
	add_child(column)
	heading = Label.new()
	heading.add_theme_font_size_override("font_size", 28)
	var title_row := HBoxContainer.new()
	column.add_child(title_row)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(heading)
	title_row.add_child(preload("res://scripts/ui_theme.gd").close_button(finish))
	progress = Label.new()
	column.add_child(progress)
	steps = ProgressBar.new()
	steps.max_value = PAGES.size()
	steps.show_percentage = false
	steps.custom_minimum_size.y = 6
	column.add_child(steps)
	picture = preload("res://scripts/guide_picture.gd").new()
	column.add_child(picture)
	body = Label.new()
	body.custom_minimum_size = Vector2(580, 210)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 23)
	column.add_child(body)
	remember = CheckButton.new()
	remember.text = "Show this guide at startup"
	remember.button_pressed = bool(config.get_value("tutorial", "show", true))
	remember.toggled.connect(func(enabled: bool): config.set_value("tutorial", "show", enabled); config.save(path))
	column.add_child(remember)
	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	previous = Button.new()
	previous.text = "Back"
	previous.pressed.connect(func(): page = maxi(0, page - 1); _page())
	buttons.add_child(previous)
	var skip := Button.new()
	skip.text = "Skip tutorial"
	skip.pressed.connect(finish)
	buttons.add_child(skip)
	next = Button.new()
	next.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	next.theme_type_variation = "PrimaryButton"
	next.pressed.connect(func():
		if page == PAGES.size() - 1: finish()
		else: page += 1; _page())
	buttons.add_child(next)
	for button in [previous, skip, next]: button.custom_minimum_size.y = 48
	hide()
func start(startup := false) -> void:
	if startup and not bool(config.get_value("tutorial", "show", true)): return
	session._close_ui()
	page = 0
	_page()
	show()
	session._place_ui()
	session._refresh_ui()
func _page() -> void:
	heading.text = PAGES[page][0]
	body.text = PAGES[page][1]
	progress.text = "Step %d of %d" % [page + 1, PAGES.size()]
	steps.value = page + 1
	picture.page = page
	previous.disabled = page == 0
	next.text = "Start playing" if page == PAGES.size() - 1 else "Next"
func finish() -> void:
	hide()
	session._refresh_ui()
