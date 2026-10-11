extends RefCounted
class_name RackHardware

static var materials: Dictionary = {}
static var wood_material: ShaderMaterial

static func finish(color: Color, metal: float = 0.0, roughness: float = 0.45) -> StandardMaterial3D:
	var key := "%s/%s/%s" % [color.to_html(), metal, roughness]
	if materials.has(key): return materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metal
	mat.roughness = roughness
	materials[key] = mat
	return mat

static func walnut() -> ShaderMaterial:
	if wood_material != null: return wood_material
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
varying vec3 local_pos;
void vertex() { local_pos = VERTEX; }
void fragment() {
    float phase = local_pos.y * 680.0 + sin(local_pos.z * 25.0) * 4.0 + sin(local_pos.y * 37.0) * 2.0;
    float footprint = fwidth(phase);
    float grain = sin(phase) * exp(-footprint * footprint * 0.2);
    float pores = fract(sin(dot(floor(local_pos.yz * vec2(2800.0, 140.0)), vec2(12.9898, 78.233))) * 43758.5453);
    pores = mix(pores, 0.5, smoothstep(0.5, 1.5, fwidth(local_pos.y * 2800.0)));
    float tone = clamp(0.5 + grain * 0.18 + pores * 0.12, 0.0, 1.0);
    ALBEDO = mix(vec3(0.12, 0.052, 0.023), vec3(0.32, 0.16, 0.072), tone);
    ROUGHNESS = 0.38 + pores * 0.12;
    SPECULAR = 0.35;
}
"""
	wood_material = ShaderMaterial.new()
	wood_material.shader = shader
	return wood_material

static func instance(parent: Node3D, mesh: Mesh, at: Vector3, mat: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.position = at
	parent.add_child(node)
	return node

static func cylinder(parent: Node3D, radius: float, depth: float, at: Vector3, mat: Material, segments: int = 48, taper: float = 1.0) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * taper
	mesh.bottom_radius = radius
	mesh.height = depth
	mesh.radial_segments = segments
	var node := instance(parent, mesh, at, mat)
	node.rotation.x = PI / 2
	return node

static func ring(parent: Node3D, inner: float, outer: float, at: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 40
	mesh.ring_segments = 12
	var node := instance(parent, mesh, at, mat)
	node.rotation.x = PI / 2
	return node

static func polygon(surface: SurfaceTool, points: Array) -> void:
	var normal: Vector3 = (points[1] - points[0]).cross(points[2] - points[0]).normalized()
	var center := Vector3.ZERO
	for point: Vector3 in points: center += point
	if normal.dot(center) < 0:
		points.reverse()
		normal = -normal
	for i in range(1, points.size() - 1):
		for point: Vector3 in [points[0], points[i], points[i + 1]]:
			surface.set_normal(normal)
			surface.set_uv(Vector2(point.x, point.y))
			surface.add_vertex(point)

static func beveled_box(size: Vector3, bevel: float = 0.002) -> ArrayMesh:
	var h := size / 2.0
	var b := minf(bevel, minf(h.x, minf(h.y, h.z)) * 0.8)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for axis in range(3):
		var u := (axis + 1) % 3
		var v := (axis + 2) % 3
		for sign_value in [-1, 1]:
			var face: Array = []
			for pair in [Vector2(h[u] - b, h[v]), Vector2(-h[u] + b, h[v]), Vector2(-h[u], h[v] - b), Vector2(-h[u], -h[v] + b), Vector2(-h[u] + b, -h[v]), Vector2(h[u] - b, -h[v]), Vector2(h[u], -h[v] + b), Vector2(h[u], h[v] - b)]:
				var point := Vector3.ZERO
				point[axis] = h[axis] * sign_value
				point[u] = pair.x
				point[v] = pair.y
				face.append(point)
			polygon(surface, face)
		for su in [-1, 1]:
			for sv in [-1, 1]:
				var edge: Array = []
				for pair in [Vector2(0, -1), Vector2(1, -1), Vector2(1, 1), Vector2(0, 1)]:
					var point := Vector3.ZERO
					point[u] = (h[u] - (b if pair.x == 0 else 0.0)) * su
					point[v] = (h[v] - (b if pair.x == 1 else 0.0)) * sv
					point[axis] = (h[axis] - b) * pair.y
					edge.append(point)
				polygon(surface, edge)
	for x in [-1, 1]:
		for y in [-1, 1]:
			for z in [-1, 1]:
				var corner: Array = []
				for axis in range(3):
					var point := (h - Vector3.ONE * b) * Vector3(x, y, z)
					point[axis] = h[axis] * [x, y, z][axis]
					corner.append(point)
				polygon(surface, corner)
	return surface.commit()

static func box(parent: Node3D, size: Vector3, at: Vector3, mat: Material, bevel: float = 0.002) -> MeshInstance3D:
	return instance(parent, beveled_box(size, bevel), at, mat)
