extends VBoxContainer
var host
var document: RichTextLabel
var picker: OptionButton
var entries := []
func setup(owner_host) -> void:
	host = owner_host
	var title := Label.new()
	title.text = "Cardinal 3D · 0.77 beta"
	title.add_theme_font_size_override("font_size", 28)
	add_child(title)
	var text := Label.new()
	text.text = "Created by mtyas · Built on DISTRHO Cardinal and Godot.\nFree software, GPL-3.0-or-later. No warranty.\nModule artwork and fonts keep their separate licences."
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(text)
	for entry in [["mtyas on GitHub", "https://github.com/mtyas"], ["Support on Ko-fi", "https://ko-fi.com/mtyas"], ["Source & releases", "https://github.com/mtyas/Cardinal-3D"]]:
		var button := Button.new()
		button.text = entry[0] + " ↗"
		button.custom_minimum_size.y = 44
		button.pressed.connect(func(): OS.shell_open(entry[1]))
		add_child(button)
	var hint := Label.new()
	hint.text = "Licence documents · Select a file, then scroll with the stick."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)
	picker = OptionButton.new()
	picker.fit_to_longest_item = false
	picker.clip_text = true
	picker.custom_minimum_size.y = 44
	add_child(picker)
	var index := "res://legal/index.json"
	if FileAccess.file_exists(index): entries = JSON.parse_string(FileAccess.get_file_as_string(index))
	for entry in entries: picker.add_item(entry.label)
	document = RichTextLabel.new()
	document.scroll_active = false
	document.fit_content = true
	document.selection_enabled = true
	document.add_theme_font_size_override("normal_font_size", 18)
	add_child(document)
	picker.item_selected.connect(_show_document)
	if not entries.is_empty(): _show_document(0)
func _show_document(index: int) -> void:
	document.text = FileAccess.get_file_as_string("res://legal/" + entries[index].path)
	if host != null: host.settings_scroll.scroll_vertical = 0
