extends RefCounted
## Shared scalable glyphs for world-space text, without temporal buffering.
static var face: SystemFont
static func font() -> SystemFont:
	if face == null:
		face = SystemFont.new()
		face.font_names = PackedStringArray(["Segoe UI", "Arial"])
		face.multichannel_signed_distance_field = true
		face.generate_mipmaps = true
	return face
static func apply(label: Label3D) -> void:
	label.font = font()
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	label.outline_size = 4
