extends Control
## Small vector diagrams are drawn only when the tutorial changes page.
var page := 0:
	set(value):
		page = value
		custom_minimum_size = Vector2(560, 280 if page in [0, 2] else 175)
		queue_redraw()
const INK := Color("d9e9f3")
const ACCENT := Color("62e4ca")
const GOLD := Color("ffcd83")
func _ready() -> void:
	custom_minimum_size = Vector2(560, 280 if page in [0, 2] else 175)
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
			controller()
		1:
			draw_circle(Vector2(110, 52), 30, INK, false, 3, true)
			line(Vector2(110, 52), Vector2(126, 31), GOLD)
			draw_arc(Vector2(110, 52), 42, -2.7, -0.1, 30, ACCENT, 3, true)
			words(Vector2(66, 110), "TWIST")
			arrow(Vector2(275, 55), Vector2(465, 55))
			arrow(Vector2(465, 55), Vector2(275, 55))
			words(Vector2(283, 110), "GRIP + TWIST · FINE")
		2:
			controller()
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
func controller() -> void:
	var image := preload("res://assets/quest2-controller.png")
	# Display the author's supplied diagram unchanged. Trim only empty canvas
	# while preserving its proportions and its existing A/B/R1/R2/R3 markers.
	var source := Rect2(280, 15, 625, 980)
	var rect := Rect2(Vector2(25, 5), source.size * (270.0 / source.size.y))
	# The supplied linework uses transparency, so its original black backing
	# is necessary for readable contours and button markers.
	draw_rect(rect, Color.BLACK)
	draw_texture_rect_region(image, rect, source)
	words(Vector2(240, 36), "RIGHT QUEST 2 TOUCH", GOLD)
	words(Vector2(240, 74), "B · Main menu")
	words(Vector2(240, 108), "A · Module browser")
	words(Vector2(240, 142), "R1 · Joystick / scroll")
	words(Vector2(240, 176), "R2 · Trigger / hold")
	words(Vector2(240, 210), "R3 · Grip / fine control", GOLD)
	words(Vector2(240, 250), "R3 + B · Module menu", GOLD)
func draw_bezier_curve(a: Vector2, b: Vector2, c: Vector2, d: Vector2, color: Color, width: float) -> void:
	var points := PackedVector2Array()
	for i in range(33): points.append(a.bezier_interpolate(b, c, d, float(i) / 32))
	draw_polyline(points, color, width, true)
