extends RefCounted

static func close_button(action: Callable) -> Button:
	var button := Button.new()
	button.name = "WindowClose"
	button.icon = icon("close")
	button.tooltip_text = "Close"
	button.custom_minimum_size = Vector2(44, 44)
	button.add_theme_constant_override("icon_max_width", 24)
	button.pressed.connect(action)
	return button

static func icon(kind: String) -> Texture2D:
	var shapes := {
		"racks": '<rect x="5" y="8" width="38" height="14" rx="2"/><rect x="5" y="27" width="38" height="14" rx="2"/><path d="M13 12v6m9-6v6m9-6v6M13 31v6m9-6v6m9-6v6"/>',
		"environment": '<circle cx="36" cy="11" r="5"/><path d="M4 39L19 12l11 19 5-9 10 17z"/>',
		"audio": '<path d="M5 23h5l5-15 6 33 7-28 6 19 5-9h5"/>',
		"modules": '<rect x="8" y="4" width="32" height="40" rx="3"/><circle cx="24" cy="17" r="7"/><path d="M24 17v-5M16 33h1m14 0h1"/>',
		"open": '<path d="M4 14h16l4 5h19l-5 22H8zM8 14V7h15l4 5h12v7"/>',
		"save": '<path d="M7 5h30l5 5v32H7zM15 5v13h18V5M15 42V27h20v15"/>',
		"undo": '<path d="M17 9L6 20l11 9M7 20h22a12 12 0 010 24"/>',
		"redo": '<path d="M31 9l11 11-11 9M41 20H19a12 12 0 000 24"/>',
		"tutorial": '<circle cx="24" cy="24" r="19"/><path d="M18 17a6 6 0 1110 5l-4 4v4m0 6v1"/>',
		"close": '<path d="M12 12l24 24M12 36l24-24"/>'
	}
	var image := Image.new()
	image.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="0 0 48 48"><g fill="none" stroke="#62e4ca" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">' + shapes.get(kind, shapes.modules) + '</g></svg>')
	return ImageTexture.create_from_image(image)

static func box(color: String, border: String = "", margin: int = 10) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color)
	style.set_corner_radius_all(12)
	style.content_margin_left = margin
	style.content_margin_right = margin
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	if not border.is_empty():
		style.border_color = Color(border)
		style.set_border_width_all(2)
	return style

static func make() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 20
	theme.default_font = preload("res://scripts/clear_text.gd").font()
	for type in ["Button", "OptionButton", "MenuButton"]:
		theme.set_stylebox("normal", type, box("203443", "365363", 16))
		theme.set_stylebox("hover", type, box("304253", "5d8498"))
		theme.set_stylebox("pressed", type, box("163d4a", "6dd9e6"))
		theme.set_stylebox("disabled", type, box("18222c"))
		var focus := box("00000000", "78dfeb")
		theme.set_stylebox("focus", type, focus)
		theme.set_color("font_color", type, Color("dfe9ef"))
		theme.set_color("font_hover_color", type, Color.WHITE)
		theme.set_color("font_disabled_color", type, Color("617382"))
	theme.set_color("font_color", "Label", Color("b6c6d2"))
	theme.set_stylebox("panel", "PanelContainer", box("101923f2", "2a3947", 16))
	theme.set_stylebox("normal", "LineEdit", box("0e1720", "344353"))
	theme.set_stylebox("focus", "LineEdit", box("12232d", "6dd9e6"))
	theme.set_color("font_color", "LineEdit", Color("e3edf4"))
	theme.set_color("font_placeholder_color", "LineEdit", Color("71889a"))
	theme.set_stylebox("panel", "PopupMenu", box("17232e", "3d5365"))
	theme.set_type_variation("PrimaryButton", "Button")
	theme.set_stylebox("normal", "PrimaryButton", box("26655f", "62e4ca", 16))
	theme.set_stylebox("hover", "PrimaryButton", box("307d72", "a5ffe4", 16))
	theme.set_stylebox("background", "ProgressBar", box("203443", "", 0))
	theme.set_stylebox("fill", "ProgressBar", box("62e4ca", "", 0))
	theme.set_constant("v_separation", "PopupMenu", 14)
	theme.set_color("font_color", "PopupMenu", Color("e3edf4"))
	theme.set_stylebox("hover", "PopupMenu", box("304253"))
	for type in ["HBoxContainer", "VBoxContainer"]:
		theme.set_constant("separation", type, 12)
	return theme
