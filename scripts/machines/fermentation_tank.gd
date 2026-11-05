extends Node3D

const MODEL := preload("res://assets/models/FermentationTank.glb")
const STYLIZED := preload("res://scripts/resources/stylized_material.gd")


func _ready() -> void:
	add_to_group(&"machine")
	if get_node_or_null(^"Model") == null:
		add_visual(self, 1.0)
	_ensure_collision()


func export_state() -> Dictionary:
	return {}


func import_state(_data: Dictionary) -> void:
	pass


static func add_visual(parent: Node3D, alpha: float, _item_id: String = "") -> Array:
	var materials: Array = []
	var visual := MODEL.instantiate() as Node3D
	if visual == null:
		return materials
	visual.name = "Model"
	parent.add_child(visual)
	if alpha < 0.99:
		_make_ghost(visual, alpha, materials)
	return materials


static func _make_ghost(root: Node, alpha: float, materials: Array) -> void:
	if root is MeshInstance3D:
		var mesh_instance := root as MeshInstance3D
		var color := _mesh_color(mesh_instance)
		var material := STYLIZED.create(color, alpha)
		mesh_instance.material_override = material
		materials.append(material)
		var mesh := mesh_instance.mesh
		if mesh != null:
			for i in mesh.get_surface_count():
				mesh_instance.set_surface_override_material(i, null)
	for child in root.get_children():
		_make_ghost(child, alpha, materials)


static func _mesh_color(mesh_instance: MeshInstance3D) -> Color:
	var color := _albedo_from(mesh_instance.material_override)
	if color != Color(-1, -1, -1, -1):
		return color
	var mesh := mesh_instance.mesh
	if mesh == null:
		return Color(0.48, 0.5, 0.54)
	for i in mesh.get_surface_count():
		color = _albedo_from(mesh_instance.get_active_material(i))
		if color != Color(-1, -1, -1, -1):
			return color
	return Color(0.48, 0.5, 0.54)


static func _albedo_from(material: Material) -> Color:
	if material is StandardMaterial3D:
		return (material as StandardMaterial3D).albedo_color
	if material is ShaderMaterial:
		var value: Variant = (material as ShaderMaterial).get_shader_parameter(&"albedo")
		if value is Color:
			return value as Color
	return Color(-1, -1, -1, -1)


func _ensure_collision() -> void:
	if get_node_or_null(^"Body") != null:
		return
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = 8
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.1, 1.15, 0.9)
	shape.shape = box
	shape.position = Vector3(0.0, 0.58, 0.0)
	body.add_child(shape)
	add_child(body)
