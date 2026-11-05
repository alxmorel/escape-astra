extends RefCounted

## Fallback si pas de Light / mesh (≈ tête blanche du torch.glb actuel).
const TIP := Vector3(0.0, 0.64, 0.0)


static func apply(host: Node3D, tip: Vector3 = Vector3.INF) -> void:
	if host == null:
		return
	var flame := host.get_node_or_null(^"Flame") as GPUParticles3D
	if flame == null:
		flame = GPUParticles3D.new()
		flame.name = "Flame"
		host.add_child(flame)
	flame.position = tip if tip.is_finite() else _resolve_tip(host)
	_configure(flame)


static func _resolve_tip(host: Node3D) -> Vector3:
	var light := host.get_node_or_null(^"Light") as Node3D
	if light != null:
		return light.position
	var model := host.get_node_or_null(^"Model") as Node3D
	if model != null:
		var top_y := -INF
		for node in model.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			var xf := model.transform * mi.transform
			var a := mi.get_aabb()
			# Tête ≈ haut du mesh, un peu sous le sommet pour rester dans le blanc.
			var y := (xf * Vector3(0.0, a.position.y + a.size.y * 0.88, 0.0)).y
			top_y = maxf(top_y, y)
		if top_y > -INF:
			return Vector3(0.0, top_y, 0.0)
	return TIP


static func _configure(flame: GPUParticles3D) -> void:
	flame.emitting = true
	flame.amount = 22
	flame.lifetime = 0.42
	flame.preprocess = 0.2
	flame.explosiveness = 0.05
	flame.randomness = 0.55
	flame.visibility_aabb = AABB(Vector3(-0.45, -0.08, -0.45), Vector3(0.9, 1.2, 0.9))
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flame.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	flame.process_material = _process_material()
	flame.draw_pass_1 = _draw_mesh()


static func _process_material() -> ParticleProcessMaterial:
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0.0, 1.0, 0.0)
	mat.spread = 16.0
	mat.flatness = 0.15
	mat.initial_velocity_min = 0.28
	mat.initial_velocity_max = 0.75
	mat.angular_velocity_min = -90.0
	mat.angular_velocity_max = 90.0
	mat.gravity = Vector3(0.0, 1.1, 0.0)
	mat.damping_min = 0.4
	mat.damping_max = 1.0
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.03
	mat.scale_min = 0.5
	mat.scale_max = 1.05
	mat.color = Color(1.0, 0.85, 0.35, 1.0)

	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.18, 0.55, 1.0])
	grad.colors = PackedColorArray([
		Color(1.0, 0.95, 0.55, 0.95),
		Color(1.0, 0.55, 0.12, 0.85),
		Color(0.85, 0.18, 0.04, 0.45),
		Color(0.15, 0.05, 0.02, 0.0),
	])
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	mat.color_ramp = ramp

	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.35))
	curve.add_point(Vector2(0.15, 1.0))
	curve.add_point(Vector2(0.7, 0.55))
	curve.add_point(Vector2(1.0, 0.0))
	var scale_tex := CurveTexture.new()
	scale_tex.curve = curve
	mat.scale_curve = scale_tex
	return mat


static func _draw_mesh() -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.13, 0.16)
	var draw := StandardMaterial3D.new()
	draw.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw.vertex_color_use_as_albedo = true
	draw.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	draw.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	draw.cull_mode = BaseMaterial3D.CULL_DISABLED
	draw.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	draw.disable_receive_shadows = true
	quad.material = draw
	return quad
