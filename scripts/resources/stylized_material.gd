extends RefCounted

const SHADER := preload("res://shaders/stylized.gdshader")
const SHADER_TRANSPARENT := preload("res://shaders/stylized_transparent.gdshader")
const SHADER_XRAY := preload("res://shaders/stylized_xray.gdshader")


static func create(color: Color, alpha := 1.0) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SHADER_TRANSPARENT if alpha < 0.99 else SHADER
	material.set_shader_parameter(&"albedo", Color(color.r, color.g, color.b, alpha))
	material.set_meta(&"base_color", Color(color.r, color.g, color.b, 1.0))
	return material


static func create_xray(alpha := 0.14) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SHADER_XRAY
	material.render_priority = -10
	material.set_shader_parameter(&"albedo", Color(0.72, 0.76, 0.8, alpha))
	material.set_meta(&"base_color", Color(0.72, 0.76, 0.8, 1.0))
	return material
