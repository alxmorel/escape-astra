extends RigidBody3D

const STYLIZED := preload("res://scripts/resources/stylized_material.gd")
const STONE_MODEL := preload("res://assets/models/rock_01.glb")
const FARM := preload("res://scripts/farming/farming_config.gd")

@export var resource_id: String = "wood"
@export var quantity: int = 1
@export var gravity_strength: float = 9.8
@export var attract_speed: float = 9.0

var pulled: bool = false

var _planet: Node3D


func _ready() -> void:
	add_to_group(&"ground_item")
	gravity_scale = 0.0
	can_sleep = false
	_planet = get_tree().get_first_node_in_group(&"planet")
	_apply_style()


func _apply_style() -> void:
	if resource_id == "wood" or resource_id.is_empty():
		return
	var visual_scene := FARM.scene_for(resource_id)
	if visual_scene != null:
		var hidden := get_node(^"MeshInstance3D") as MeshInstance3D
		hidden.visible = false
		var visual := visual_scene.instantiate()
		visual.name = "Visual"
		add_child(visual)
		return
	var mesh_node := get_node(^"MeshInstance3D") as MeshInstance3D
	var shape_node := get_node(^"CollisionShape3D") as CollisionShape3D
	mesh_node.visible = false
	if resource_id == "stone":
		var model := STONE_MODEL.instantiate() as Node3D
		model.scale = Vector3.ONE * 0.2
		add_child(model)
		var bounds := _mesh_bounds(model)
		var center := bounds.get_center()
		model.position -= center
		model.position.y -= bounds.position.y
		var shape := BoxShape3D.new()
		shape.size = bounds.size * 0.9
		shape_node.shape = shape
		shape_node.transform = Transform3D.IDENTITY
		return
	var box := BoxMesh.new()
	box.size = Vector3(0.26, 0.2, 0.22)
	mesh_node.mesh = box
	mesh_node.transform = Transform3D.IDENTITY
	mesh_node.visible = true
	mesh_node.material_override = STYLIZED.create(Color(0.62, 0.62, 0.62))
	var shape := BoxShape3D.new()
	shape.size = box.size
	shape_node.shape = shape
	shape_node.transform = Transform3D.IDENTITY


func _mesh_bounds(root: Node3D) -> AABB:
	var merged := AABB()
	var started := false
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null:
			continue
		var local_box := mesh_node.get_aabb()
		var xform := mesh_node.transform
		var parent := mesh_node.get_parent() as Node3D
		while parent != null and parent != root:
			xform = parent.transform * xform
			parent = parent.get_parent() as Node3D
		for i in 8:
			var corner: Vector3 = xform * local_box.get_endpoint(i)
			if not started:
				merged = AABB(corner, Vector3.ZERO)
				started = true
			else:
				merged = merged.expand(corner)
	return merged


func pull_toward(target: Vector3) -> void:
	pulled = true
	var to_target := target - global_position
	if to_target.length_squared() < 0.0001:
		return
	linear_velocity = to_target.normalized() * minf(attract_speed, to_target.length() * 10.0)
	angular_velocity = Vector3.ZERO


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if pulled or _planet == null:
		return
	var offset: Vector3 = state.transform.origin - _planet.global_position
	var distance := offset.length()
	if distance < 0.001:
		return
	var up := offset / distance
	state.linear_velocity += -up * gravity_strength * state.step
	if not _planet.has_method(&"get_walk_radius"):
		return
	var ground_radius: float = _planet.call(&"get_walk_radius", offset)
	if distance >= ground_radius + 0.12:
		return
	state.transform.origin = _planet.global_position + up * (ground_radius + 0.16)
	if state.linear_velocity.dot(up) < 0.0:
		state.linear_velocity -= up * state.linear_velocity.dot(up)
