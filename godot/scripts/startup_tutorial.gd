extends PanelContainer
const PAGES := [
	["Welcome to Cardinal 3D", "Point a controller’s ray at a control. Use the trigger to click or hold.\n\nYou can skip this guide now and open it again from the B menu."],
	["Knobs & faders", "Point at a knob or fader and hold the trigger. Twist your wrist to adjust it.\n\nMove closer or farther while holding for finer adjustment; the meter shows your movement. Wrist speed is adjustable in the main menu."],
	["Browse & menus", "A opens the module browser. Use the joystick to scroll, click a module, then choose Add.\n\nB opens the main menu. Select a module by its top strip, then B opens its own menu. Grip + B always opens the main menu."],
	["Move your viewpoint", "The joystick pans left/right and moves closer/farther.\n\nHold the grip: up/down raises or lowers you; left/right turns your view. In menus, the joystick scrolls instead."],
	["Modules & cables", "Hold a module’s top strip to show its placement ghost. Release to place it.\n\nHold an output socket and release on an input to connect a cable. Grab an input plug, pull it clear, and release away from sockets to unplug it."],
	["Arrange your racks", "Open B → Rack management and enable Layout mode. Choose a rack or click its case edge. Add creates a case beside it.\n\nHold a case edge to move it; turn your hand left/right to rotate it upright. Switch Layout mode off before performing."],
	["Places, devices & saving", "Environment & graphics chooses your surroundings and time of day. Audio & MIDI devices has its own menu.\n\nUse Open patch and Save patch as in the main menu. Keep the .3d.json file beside the patch to retain the case arrangement."]
]
var session
var page := 0
var heading: Label
var body: Label
var progress: Label
var previous: Button
var next: Button
var remember: CheckButton
var config := ConfigFile.new()
var path := ""
func setup(owner_session) -> void:
	session = owner_session
	position = Vector2(410, 160)
	custom_minimum_size = Vector2(620, 0)
	theme = preload("res://scripts/ui_theme.gd").make()
	var directory := OS.get_environment("CARDINAL_EMBEDDED_USER_DIR")
	path = directory.path_join("tutorial.cfg") if not directory.is_empty() else "user://tutorial.cfg"
	config.load(path)
	var column := VBoxContainer.new()
	add_child(column)
	heading = Label.new()
	heading.add_theme_font_size_override("font_size", 28)
	column.add_child(heading)
	progress = Label.new()
	column.add_child(progress)
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
	previous.disabled = page == 0
	next.text = "Start playing" if page == PAGES.size() - 1 else "Next"
func finish() -> void:
	hide()
	session._refresh_ui()
