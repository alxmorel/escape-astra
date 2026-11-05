extends "res://scripts/resources/harvestable.gd"

const ProceduralTree := preload("res://scripts/world/procedural_tree.gd")
const TRUNK_SCENE := preload("res://assets/models/tronc_arbre.glb")
const OBSTACLE_LAYER := 8

@export var segment_hits: int = 2

var _radius: float = ProceduralTree.TRUNK_RADIUS * 0.72


func setup(world_xf: Transform3D, radius: float, _toward: Vector3 = Vector3.ZERO) -> void:
	resource_id = "wood"
	required_tool = "axe"
	max_hits = maxi(segment_hits, 1)
	hits_per_drop = max_hits
	drop_quantity = 1
	aim_height = ProceduralTree.TRUNK_HEIGHT * 0.5
	chip_color = Color(0.55, 0.34, 0.16)
	_radius = maxf(radius * 0.7, 0.22)
	global_transform = Transform3D(world_xf.basis.orthonormalized(), world_xf.origin)
	_add_visual()
	_add_collision()


func _ready() -> void:
	super._ready()
	name = "FallenTrunkSegment"


func receive_hit(tool_id: String = "", _hit_point: Variant = null) -> bool:
	if not _accepts_tool(tool_id):
		return false
	hits += 1
	_spawn_chips()
	if hits_per_drop > 0 and hits % hits_per_drop == 0:
		_spawn_drop()
	if hits >= max_hits:
		queue_free()
		return true
	var base_scale := scale
	var tween := create_tween()
	tween.tween_property(self, "scale", base_scale * Vector3(1.06, 0.92, 1.06), 0.05)
	tween.tween_property(self, "scale", base_scale, 0.08)
	return true


func aim_point() -> Vector3:
	return global_position + global_transform.basis.y.normalized() * (ProceduralTree.TRUNK_HEIGHT * 0.5)


func _add_visual() -> void:
	var visual := TRUNK_SCENE.instantiate() as Node3D
	visual.name = "Tronc"
	add_child(visual)


func _add_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "SegmentCollision"
	body.collision_layer = OBSTACLE_LAYER
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.height = ProceduralTree.TRUNK_HEIGHT * 0.92
	cylinder.radius = _radius * 0.82
	collision.shape = cylinder
	collision.position = Vector3(0.0, ProceduralTree.TRUNK_HEIGHT * 0.5, 0.0)
	body.add_child(collision)
	add_child(body)


func _spawn_drop() -> void:
	var item := GROUND_ITEM_SCENE.instantiate()
	item.resource_id = resource_id
	item.quantity = drop_quantity
	get_tree().current_scene.add_child(item)
	var mid := aim_point()
	var axis := global_transform.basis.y.normalized()
	var side := global_transform.basis.x.normalized()
	if side.length_squared() < 0.001:
		side = axis.cross(Vector3.UP).normalized()
	item.global_position = mid + side * 0.15
	item.linear_velocity = side * randf_range(0.5, 1.1) + axis * randf_range(0.2, 0.6)
