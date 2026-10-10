extends Control

var center := Vector2.ZERO
var radius := 20.0
var active := false
var title_strip := false
var title_rect := Rect2()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	if title_strip:
		draw_style_box(_title_style(), title_rect)
	if not active: return
	var cyan := Color(0.35, 0.88, 1.0, 0.95)
	draw_arc(center, radius + 3, 0, TAU, 64, Color(0.04, 0.08, 0.12, 0.8), 5, true)
	draw_arc(center, radius + 3, 0, TAU, 64, cyan, 2, true)
	for axis in [Vector2.RIGHT, Vector2.DOWN]:
		draw_line(center - axis * 4, center + axis * 4, cyan, 1.5, true)

func _title_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.25, 0.7, 0.9, 0.12)
	style.border_color = Color(0.35, 0.88, 1.0, 0.7)
	style.set_border_width_all(1)
	return style
