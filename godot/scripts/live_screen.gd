extends Node3D

const Hardware := preload("res://scripts/hardware.gd")
const SCALE := 0.002
var display_material: ShaderMaterial

func setup(region: Dictionary, panel_size: Vector2) -> void:
	var width := float(region["width"]) * SCALE
	var height := float(region["height"]) * SCALE
	position = Vector3((float(region["x"]) + float(region["width"]) / 2) * SCALE, -(float(region["y"]) + float(region["height"]) / 2) * SCALE, 0)
	var rim := 0.003
	var anodized := Hardware.finish(Color("151d24"), 0.65, 0.32)
	Hardware.box(self, Vector3(width + rim * 2, height + rim * 2, 0.008), Vector3(0, 0, 0.002), Hardware.finish(Color("05090d"), 0.1, 0.65), 0.0015)
	for x in [-width / 2 - rim / 2, width / 2 + rim / 2]:
		Hardware.box(self, Vector3(rim, height + rim * 2, 0.012), Vector3(x, 0, 0.006), anodized, 0.0008)
	for y in [-height / 2 - rim / 2, height / 2 + rim / 2]:
		Hardware.box(self, Vector3(width, rim, 0.012), Vector3(0, y, 0.006), anodized, 0.0008)
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
uniform sampler2D panel_texture : source_color, filter_linear_mipmap;
uniform vec4 region_uv;
uniform float pixel_height;
uniform bool meter = false;
void fragment() {
    vec3 native = texture(panel_texture, region_uv.xy + UV * region_uv.zw).rgb;
    // Subtle optical detail only; all traces, readings and meter values are native.
    float phase = UV.y * pixel_height * 3.14159;
    float footprint = fwidth(phase);
    float scan = meter ? 1.0 : 0.97 + 0.03 * cos(phase) * exp(-footprint * footprint * 0.2);
    float edge = smoothstep(0.0, 0.015, min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y)));
    float sheen = pow(clamp(1.0 - abs(UV.x * 0.7 + UV.y - 0.28) * 9.0, 0.0, 1.0), 3.0) * 0.025;
    ALBEDO = vec3(0.015, 0.023, 0.03) + native * 0.04 + sheen;
    EMISSION = native * scan * mix(0.85, 1.0, edge);
    ROUGHNESS = 0.19;
    SPECULAR = 0.75;
}
"""
	display_material = ShaderMaterial.new()
	display_material.shader = shader
	display_material.set_shader_parameter("region_uv", Vector4(float(region["x"]) / panel_size.x, float(region["y"]) / panel_size.y, float(region["width"]) / panel_size.x, float(region["height"]) / panel_size.y))
	display_material.set_shader_parameter("pixel_height", float(region["height"]))
	display_material.set_shader_parameter("meter", str(region["kind"]) == "meter")
	var glass := QuadMesh.new()
	glass.size = Vector2(width, height)
	var node := Hardware.instance(self, glass, Vector3(0, 0, 0.0065), display_material)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func apply_texture(texture: Texture2D) -> void:
	display_material.set_shader_parameter("panel_texture", texture)
