extends RefCounted

static func box(color: String, border: String = "", margin: int = 10) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color)
	style.set_corner_radius_all(7)
	style.content_margin_left = margin
	style.content_margin_right = margin
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	if not border.is_empty():
		style.border_color = Color(border)
		style.set_border_width_all(1)
	return style

static func make() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 14
	for type in ["Button", "OptionButton", "MenuButton"]:
		theme.set_stylebox("normal", type, box("202c38", "344353"))
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
	theme.set_stylebox("hover", "PopupMenu", box("304253"))
	for type in ["HBoxContainer", "VBoxContainer"]:
		theme.set_constant("separation", type, 8)
	return theme
