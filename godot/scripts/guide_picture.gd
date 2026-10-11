extends Control
## Small vector diagrams are drawn only when the tutorial changes page.
var page := 0:
	set(value):
		page = value
		queue_redraw()
const INK := Color("d9e9f3")
const ACCENT := Color("62e4ca")
const GOLD := Color("ffcd83")
func _ready() -> void:
	custom_minimum_size = Vector2(560, 125)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
func line(a: Vector2, b: Vector2, color := ACCENT) -> void: draw_line(a, b, color, 3, true)
func words(at: Vector2, text: String, color := INK) -> void:
	draw_string(preload("res://scripts/clear_text.gd").font(), at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, color)
func arrow(a: Vector2, b: Vector2) -> void:
	line(a, b)
	var d := (a - b).normalized()
	line(b, b + d.rotated(0.6) * 12)
	line(b, b + d.rotated(-0.6) * 12)
func rack(at: Vector2) -> void:
	draw_rect(Rect2(at, Vector2(100, 62)), INK, false, 3)
	for x in [18, 50, 82]:
		draw_circle(at + Vector2(x, 22), 9, ACCENT, false, 2, true)
		draw_circle(at + Vector2(x, 48), 4, GOLD)
func _draw() -> void:
	draw_style_box(preload("res://scripts/ui_theme.gd").box("102d39", "285669", 12), Rect2(Vector2.ZERO, size))
	match page:
		0:
			rack(Vector2(360, 25))
			draw_circle(Vector2(80, 60), 22, INK, false, 3, true)
			arrow(Vector2(106, 60), Vector2(350, 60))
			words(Vector2(135, 98), "POINT  +  TRIGGER", ACCENT)
		1:
			draw_circle(Vector2(110, 52), 30, INK, false, 3, true)
			line(Vector2(110, 52), Vector2(126, 31), GOLD)
			draw_arc(Vector2(110, 52), 42, -2.7, -0.1, 30, ACCENT, 3, true)
			words(Vector2(66, 110), "TWIST")
			arrow(Vector2(275, 55), Vector2(465, 55))
			arrow(Vector2(465, 55), Vector2(275, 55))
			words(Vector2(283, 110), "PUSH / PULL · FINE")
		2:
			for x in [95, 345]: draw_circle(Vector2(x, 48), 29, ACCENT if x == 95 else GOLD)
			words(Vector2(88, 56), "A", Color("10202d")); words(Vector2(338, 56), "B", Color("10202d"))
			words(Vector2(55, 107), "BROWSER"); words(Vector2(315, 107), "MENUS")
		3:
			arrow(Vector2(190, 60), Vector2(95, 60)); arrow(Vector2(190, 60), Vector2(285, 60))
			arrow(Vector2(190, 60), Vector2(190, 15)); arrow(Vector2(190, 60), Vector2(190, 105))
			words(Vector2(330, 48), "STICK · PAN / ZOOM")
			words(Vector2(330, 80), "GRIP · RISE / TURN", GOLD)
		4:
			rack(Vector2(50, 25)); rack(Vector2(405, 25))
			draw_bezier_curve(Vector2(132, 73), Vector2(210, 126), Vector2(325, 126), Vector2(423, 73), ACCENT, 3)
			words(Vector2(188, 36), "HOLD → RELEASE", GOLD)
		5:
			rack(Vector2(230, 32))
			arrow(Vector2(215, 62), Vector2(145, 62)); arrow(Vector2(345, 62), Vector2(415, 62))
			arrow(Vector2(280, 25), Vector2(280, 5)); arrow(Vector2(280, 98), Vector2(280, 120))
			words(Vector2(18, 112), "FREE MOVEMENT"); words(Vector2(380, 112), "UPRIGHT TURN", GOLD)
		6:
			draw_circle(Vector2(95, 42), 16, GOLD)
			line(Vector2(30, 92), Vector2(130, 22)); line(Vector2(130, 22), Vector2(215, 92))
			rack(Vector2(370, 24))
			words(Vector2(240, 65), "YOUR SPACE", ACCENT)
func draw_bezier_curve(a: Vector2, b: Vector2, c: Vector2, d: Vector2, color: Color, width: float) -> void:
	var points := PackedVector2Array()
	for i in range(33): points.append(a.bezier_interpolate(b, c, d, float(i) / 32))
	draw_polyline(points, color, width, true)
