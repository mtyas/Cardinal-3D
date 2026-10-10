extends Node3D
class_name CardinalRackCase

const Hardware := preload("res://scripts/hardware.gd")
const SCALE := 0.002
const HP := 15.0
var layout_signature := ""
var bounds := Rect2()

func sync(descriptions: Array) -> void:
	var layout: Array = []
	for module: Dictionary in descriptions:
		layout.append([module["x"], module["y"], module["width"], module["height"]])
	var signature := JSON.stringify(layout)
	if signature == layout_signature: return
	layout_signature = signature
	for child in get_children():
		remove_child(child)
		child.queue_free()
	if descriptions.is_empty():
		bounds = Rect2()
		return
	var first := true
	var rows: Dictionary = {}
	for module: Dictionary in descriptions:
		var rect := Rect2(float(module["x"]), float(module["y"]), float(module["width"]), float(module["height"]))
		bounds = rect if first else bounds.merge(rect)
		first = false
		rows["%s/%s" % [rect.position.y, rect.size.y]] = rect
	# Allow one HP of empty space on either side; never change native module positions.
	var left := (floorf(bounds.position.x / HP) - 1) * HP * SCALE
	var right := (ceilf(bounds.end.x / HP) + 1) * HP * SCALE
	var top := -bounds.position.y * SCALE + 0.024
	var bottom := -bounds.end.y * SCALE - 0.024
	var width := right - left
	var height := top - bottom
	var center := Vector3((left + right) / 2, (top + bottom) / 2, -0.1)
	var aluminum := Hardware.finish(Color("8a949d"), 0.88, 0.3)
	var dark_metal := Hardware.finish(Color("22282d"), 0.72, 0.4)
	Hardware.box(self, Vector3(width, height, 0.012), center + Vector3(0, 0, -0.086), dark_metal)
	for x in [left - 0.02, right + 0.02]:
		Hardware.box(self, Vector3(0.04, height + 0.04, 0.23), Vector3(x, center.y, -0.087), Hardware.walnut(), 0.006)
	for y in [top + 0.008, bottom - 0.008]:
		Hardware.box(self, Vector3(width, 0.026, 0.19), Vector3(center.x, y, -0.095), dark_metal, 0.004)
	for row: Rect2 in rows.values():
		for y in [-row.position.y * SCALE + 0.007, -row.end.y * SCALE - 0.007]:
			Hardware.box(self, Vector3(width, 0.026, 0.035), Vector3(center.x, y, -0.025), aluminum, 0.003)
			# Continuous extruded mounting channel with threaded-strip detail.
			Hardware.box(self, Vector3(width - 0.008, 0.003, 0.0015), Vector3(center.x, y, -0.0065), dark_metal, 0.0003)
			for x in range(int(ceilf(left / (HP * SCALE))), int(floorf(right / (HP * SCALE))) + 1):
				Hardware.cylinder(self, 0.0015, 0.001, Vector3(x * HP * SCALE, y, -0.005), dark_metal, 12)
	# A visible end-cap fastener at each corner.
	for x in [left - 0.019, right + 0.019]:
		for y in [top - 0.012, bottom + 0.012]:
			Hardware.cylinder(self, 0.0045, 0.002, Vector3(x, y, 0.029), aluminum)
			Hardware.box(self, Vector3(0.006, 0.001, 0.0008), Vector3(x, y, 0.0305), dark_metal, 0.0002)
	# Case bounds include the cheeks and rails for framing.
	bounds = Rect2(left / SCALE - 20, -(top + 0.024) / SCALE, (width + 0.08) / SCALE, (height + 0.048) / SCALE)
