extends "res://scripts/main.gd"

var cursor_targets: Array[Vector2] = []
var cursor_latches: Array[String] = []

func _snap_cursor(position: Vector2) -> void:
	cursor_targets.append(position)
	cursor_latches.append(magnet_latched)
