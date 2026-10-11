extends Node3D
class_name CardinalModuleView

const SCALE := 0.002
const Hardware := preload("res://scripts/hardware.gd")
const LiveScreen := preload("res://scripts/live_screen.gd")
var descriptor: Dictionary
var face: MeshInstance3D
var texture: ImageTexture
var knobs: Dictionary = {}
var lights: Dictionary = {}
var switches: Dictionary = {}
var screens: Array = []
var control_nodes: Dictionary = {}
var selection_strip: MeshInstance3D

func set_selected(selected: bool) -> void:
	if selection_strip == null:
		var strip := QuadMesh.new()
		strip.size = Vector2(float(descriptor.get("width", 90)) * SCALE, 0.006)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color("83e7ed")
		selection_strip = mesh_node(strip, Vector3(strip.size.x / 2, -0.009, 0.007), mat)
	selection_strip.visible = selected

static func control_key(control: Dictionary) -> String:
	return "%s/%s/%s" % [control["kind"], control["id"], control.get("direction", "")]

static func material(color: Color, metal: float = 0.0) -> StandardMaterial3D:
	return Hardware.finish(color, metal, 0.28 if metal > 0 else 0.55)

func mesh_node(mesh: Mesh, at: Vector3, mat: Material, parent_node: Node3D = self) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.position = at
	parent_node.add_child(node)
	return node

func cylinder(radius: float, depth: float, at: Vector3, mat: Material, parent_node: Node3D = self) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = depth
	mesh.radial_segments = 32
	var node := mesh_node(mesh, at, mat, parent_node)
	node.rotation.x = PI / 2
	return node

func setup(data: Dictionary) -> void:
	descriptor = data
	position = Vector3(float(data["x"]) * SCALE, -float(data["y"]) * SCALE, 0)
	var width := float(data["width"]) * SCALE
	var height := float(data["height"]) * SCALE
	Hardware.box(self, Vector3(width - 0.0006, height - 0.0006, 0.008), Vector3(width / 2, -height / 2, -0.0035), material(Color("79838b"), 0.85), 0.0008)
	var panel := QuadMesh.new()
	panel.size = Vector2(width, height)
	face = mesh_node(panel, Vector3(width / 2, -height / 2, 0.001), material(Color("b5bdc2"), 0.4))
	var hit_body := StaticBody3D.new()
	hit_body.set_meta("module_view", self)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, height, 0.022)
	collision.shape = shape
	collision.position = Vector3(width / 2, -height / 2, -0.01)
	hit_body.add_child(collision)
	add_child(hit_body)
	for region: Dictionary in data.get("screens", []):
		var display := LiveScreen.new()
		add_child(display)
		display.setup(region, Vector2(float(data["width"]), float(data["height"])))
		screens.append(display)
	for control: Dictionary in data.get("controls", []):
		var at := Vector3(float(control["x"]) * SCALE, -float(control["y"]) * SCALE, 0.014)
		var radius := maxf(float(control["width"]) * SCALE / 2, 0.005)
		var kind := str(control["kind"])
		if not control.get("physical", false) and kind != "light":
			continue
		var first_child := get_child_count()
		if kind == "knob":
			var face_color := Color(str(control.get("body_color", "#333c45")))
			var pivot := Node3D.new()
			pivot.position = at
			add_child(pivot)
			Hardware.cylinder(pivot, radius * 1.04, 0.004, Vector3(0, 0, -0.009), Hardware.finish(Color("161b20"), 0.15, 0.4))
			Hardware.cylinder(pivot, radius, 0.023, Vector3.ZERO, Hardware.finish(face_color.darkened(0.18), 0.05, 0.38), 64, 0.9)
			Hardware.ring(pivot, radius * 0.86, radius * 0.94, Vector3(0, 0, 0.011), Hardware.finish(Color("424a51"), 0.65, 0.26))
			var cap := cylinder(radius * 0.86, 0.003, Vector3(0, 0, 0.012), Hardware.finish(face_color, 0.18, 0.34), pivot)
			cap.name = "ColourCap"
			# Grip flutes use one instanced draw rather than dozens of separate nodes.
			var ribs := MultiMesh.new()
			ribs.transform_format = MultiMesh.TRANSFORM_3D
			var rib := BoxMesh.new()
			rib.size = Vector3(radius * 0.07, 0.0014, 0.019)
			ribs.mesh = rib
			ribs.instance_count = 40
			for index in range(40):
				var angle := TAU * index / 40.0
				ribs.set_instance_transform(index, Transform3D(Basis(Vector3.FORWARD, -angle), Vector3(sin(angle) * radius * 0.95, cos(angle) * radius * 0.95, -0.001)))
			var grip := MultiMeshInstance3D.new()
			grip.multimesh = ribs
			grip.material_override = Hardware.finish(Color("171d22"), 0.0, 0.55)
			pivot.add_child(grip)
			var mark := BoxMesh.new()
			mark.size = Vector3(radius * 0.16, radius * 0.57, 0.002)
			var indicator := StandardMaterial3D.new()
			indicator.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			var brightness := face_color.r * 0.2126 + face_color.g * 0.7152 + face_color.b * 0.0722
			indicator.albedo_color = Color.BLACK if brightness > 0.5 else Color("f4fff8")
			var marker := mesh_node(mark, Vector3(0, radius * 0.58, 0.018), indicator, pivot)
			marker.name = "ValueIndicator"
			marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			knobs[str(control["id"])] = {"node": pivot, "control": control}
		elif kind == "port":
			var steel := Hardware.finish(Color("b6c0c9"), 0.95, 0.22)
			Hardware.cylinder(self, radius * 0.88, 0.005, at - Vector3(0, 0, 0.007), steel, 6)
			Hardware.ring(self, radius * 0.44, radius * 0.7, at - Vector3(0, 0, 0.002), steel)
			Hardware.cylinder(self, radius * 0.43, 0.004, at - Vector3(0, 0, 0.005), Hardware.finish(Color("080b0e"), 0, 0.9))
			Hardware.ring(self, radius * 0.31, radius * 0.37, at - Vector3(0, 0, 0.003), Hardware.finish(Color("75623c"), 0.85, 0.3))
		elif kind == "screw":
			Hardware.ring(self, radius * 0.48, radius * 0.78, at - Vector3(0, 0, 0.01), Hardware.finish(Color("747f88"), 0.9, 0.3))
			Hardware.cylinder(self, radius * 0.65, 0.003, at - Vector3(0, 0, 0.009), Hardware.finish(Color("b3bcc3"), 0.95, 0.23), 48, 0.85)
			for size in [Vector3(radius, radius * 0.13, 0.0008), Vector3(radius * 0.13, radius, 0.0008)]:
				Hardware.box(self, size, at - Vector3(0, 0, 0.007), material(Color("262b30")), 0.0002)
		elif kind == "light":
			var bulb := SphereMesh.new()
			bulb.radius = radius * 0.65
			bulb.height = radius * 1.3
			Hardware.ring(self, radius * 0.6, radius * 0.76, at - Vector3(0, 0, 0.009), material(Color("78828a"), 0.8))
			# Lights have independent materials because their emission changes per instance.
			var lens := Hardware.finish(Color("142523")).duplicate() as StandardMaterial3D
			lens.clearcoat_enabled = true
			lens.clearcoat = 0.7
			lens.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			var node := mesh_node(bulb, at - Vector3(0, 0, 0.008), lens)
			lights[str(control["id"])] = node
		elif kind == "switch" or kind == "button":
			var size := Vector3(float(control["width"]) * SCALE * 0.8, float(control["height"]) * SCALE * 0.8, 0.012)
			switches[str(control["id"])] = Hardware.box(self, size, at, Hardware.finish(Color("46515d"), 0.1, 0.35), 0.002)
		elif kind == "slider":
			var start := Vector3(float(control.get("start_x", control["x"])) * SCALE, -float(control.get("start_y", control["y"])) * SCALE, 0.003)
			var end := Vector3(float(control.get("end_x", control["x"])) * SCALE, -float(control.get("end_y", control["y"])) * SCALE, 0.003)
			Hardware.box(self, Vector3(maxf(absf(end.x - start.x), 0.004), maxf(absf(end.y - start.y), 0.004), 0.003), (start + end) / 2, material(Color("0b1015")), 0.0005)
			var size := Vector3(float(control.get("handle_width", control["width"])) * SCALE, float(control.get("handle_height", 6)) * SCALE, 0.016)
			var handle := Hardware.box(self, size, at, Hardware.finish(Color("535f69"), 0.5, 0.33), 0.002)
			knobs[str(control["id"])] = {"node": handle, "control": control}
		var group := Node3D.new()
		var geometry := get_children().slice(first_child)
		add_child(group)
		for child in geometry: child.reparent(group)
		control_nodes[control_key(control)] = group
	update_state(data)

func update_state(data: Dictionary) -> void:
	descriptor = data
	position.x = float(data["x"]) * SCALE
	position.y = -float(data["y"]) * SCALE
	for control: Dictionary in data.get("controls", []):
		var id := str(control["id"])
		var key := control_key(control)
		if control_nodes.has(key): control_nodes[key].visible = control.get("visible", true)
		if control["kind"] in ["knob", "slider"] and knobs.has(id):
			var entry: Dictionary = knobs[id]
			var fraction := float(control.get("normalized", 0))
			if control["kind"] == "knob":
				entry["node"].rotation.z = -lerpf(float(control.get("min_angle", -2.6)), float(control.get("max_angle", 2.6)), fraction)
			else:
				entry["node"].position.x = lerpf(float(control.get("start_x", control["x"])), float(control.get("end_x", control["x"])), fraction) * SCALE
				entry["node"].position.y = -lerpf(float(control.get("start_y", control["y"])), float(control.get("end_y", control["y"])), fraction) * SCALE
		if control["kind"] in ["switch", "button"] and switches.has(id):
			var fraction := float(control.get("normalized", 0))
			switches[id].rotation.x = lerpf(-0.3, 0.3, fraction)
		if control["kind"] == "light" and lights.has(id):
			var brightness := clampf(float(control.get("brightness", 0)), 0, 1)
			var mat: StandardMaterial3D = lights[id].material_override
			var light_color := Color(str(control.get("color", "#17d6b2")))
			var emission := Color(float(control.get("emission_r", light_color.r * brightness)), float(control.get("emission_g", light_color.g * brightness)), float(control.get("emission_b", light_color.b * brightness)))
			mat.albedo_color = Color(0.025, 0.025, 0.025) + emission
			mat.emission_enabled = true
			mat.emission = emission

func apply_surface(image: Image) -> void:
	# Spatial mipmaps suppress shimmering at distance and oblique angles without
	# buffering controller changes or delaying live control/LED updates.
	if not image.has_mipmaps(): image.generate_mipmaps()
	if texture == null:
		texture = ImageTexture.create_from_image(image)
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = texture
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		mat.metallic = 0.22
		mat.roughness = 0.48
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		face.material_override = mat
	else:
		if texture.get_width() == image.get_width() and texture.get_height() == image.get_height():
			texture.update(image)
		else:
			texture.set_image(image)
	for display in screens:
		display.apply_texture(texture)

func pixel_at(world_point: Vector3) -> Vector2:
	var point := to_local(world_point)
	return Vector2(point.x / SCALE, -point.y / SCALE)

func port_position(port_id: int, direction: String) -> Vector3:
	for control: Dictionary in descriptor.get("controls", []):
		if control["kind"] == "port" and int(control["id"]) == port_id and control["direction"] == direction:
			return to_global(Vector3(float(control["x"]) * SCALE, -float(control["y"]) * SCALE, 0.026))
	return global_position
