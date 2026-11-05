extends "res://scripts/resources/harvestable.gd"

## Tronc couché d'un bloc : feuillage conservé jusqu'à la dernière bûche.
const ProceduralTree := preload("res://scripts/world/procedural_tree.gd")
const OBSTACLE_LAYER := 8
const SEGMENT_HITS := 2

var trunk_xforms: Array[Transform3D] = []
var foliage_a: Array[Transform3D] = []
var foliage_b: Array[Transform3D] = []
var trunk_radius: float = ProceduralTree.TRUNK_RADIUS

var _alive: Array[bool] = []
var _damage: PackedInt32Array = PackedInt32Array()
var _visual: Node3D
var _collision_body: StaticBody3D


func setup(
	world_xform: Transform3D,
	trunks: Array[Transform3D],
	leaves_a: Array[Transform3D],
	leaves_b: Array[Transform3D],
	radius: float
) -> void:
	resource_id = "wood"
	required_tool = "axe"
	hits_per_drop = 0
	drop_quantity = 1
	chip_color = Color(0.55, 0.34, 0.16)
	trunk_radius = radius
	trunk_xforms = trunks.duplicate()
	foliage_a = leaves_a.duplicate()
	foliage_b = leaves_b.duplicate()
	_alive.clear()
	_damage = PackedInt32Array()
	_damage.resize(trunk_xforms.size())
	for i in trunk_xforms.size():
		_alive.append(true)
		_damage[i] = 0
	global_transform = world_xform
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	_refresh_visual()
	_rebuild_collision()
	aim_height = 0.4


func receive_hit(tool_id: String = "", hit_point: Variant = null) -> bool:
	if not _accepts_tool(tool_id):
		return false
	if _alive_count() <= 0:
		return false
	var local_point := Vector3(0.0, 0.4, 0.0)
	if hit_point is Vector3:
		local_point = to_local(hit_point as Vector3)
	var idx := _nearest_alive(local_point)
	if idx < 0:
		return false
	_damage[idx] += 1
	var xf := trunk_xforms[idx]
	var mid := ProceduralTree.segment_mid(xf)
	_spawn_chips_at(to_global(mid))
	if _damage[idx] < SEGMENT_HITS:
		return true
	_destroy_segment(idx)
	return true


func aim_point() -> Vector3:
	for i in trunk_xforms.size():
		if _alive[i]:
			return to_global(ProceduralTree.segment_mid(trunk_xforms[i]))
	return global_position


func _alive_count() -> int:
	var n := 0
	for a in _alive:
		if a:
			n += 1
	return n


func _nearest_alive(local_point: Vector3) -> int:
	var best := -1
	var best_dist := INF
	for i in trunk_xforms.size():
		if not _alive[i]:
			continue
		var xf := trunk_xforms[i]
		var axis := xf.basis.y.normalized()
		var along := clampf((local_point - xf.origin).dot(axis), 0.0, ProceduralTree.TRUNK_HEIGHT)
		var closest := xf.origin + axis * along
		var dist := closest.distance_squared_to(local_point)
		if dist < best_dist:
			best_dist = dist
			best = i
	return best


func _destroy_segment(idx: int) -> void:
	if idx < 0 or idx >= _alive.size() or not _alive[idx]:
		return
	_alive[idx] = false
	_spawn_wood_at(to_global(ProceduralTree.segment_mid(trunk_xforms[idx])))
	if _alive_count() <= 0:
		# Dernière bûche : feuillage disparaît avec l'assemblage.
		queue_free()
		return
	_refresh_visual()
	_rebuild_collision()


func _refresh_visual() -> void:
	if _visual == null:
		return
	var trunks: Array[Transform3D] = []
	for i in trunk_xforms.size():
		if _alive[i]:
			trunks.append(trunk_xforms[i])
	# Feuillage tant qu'il reste au moins une bûche.
	ProceduralTree.fill_visual(_visual, trunks, foliage_a, foliage_b)


func _rebuild_collision() -> void:
	if _collision_body != null and is_instance_valid(_collision_body):
		_collision_body.queue_free()
		_collision_body = null
	_collision_body = StaticBody3D.new()
	_collision_body.name = "AssemblyCollision"
	_collision_body.collision_layer = OBSTACLE_LAYER
	_collision_body.collision_mask = 0
	for i in trunk_xforms.size():
		if not _alive[i]:
			continue
		var xf := trunk_xforms[i]
		var collision := CollisionShape3D.new()
		var cylinder := CylinderShape3D.new()
		cylinder.height = ProceduralTree.TRUNK_HEIGHT * 0.92
		cylinder.radius = maxf(trunk_radius * 0.7, 0.18)
		collision.shape = cylinder
		collision.transform = Transform3D(xf.basis, xf.origin + xf.basis.y * (ProceduralTree.TRUNK_HEIGHT * 0.5))
		_collision_body.add_child(collision)
	add_child(_collision_body)


func _spawn_wood_at(origin: Vector3) -> void:
	var item := GROUND_ITEM_SCENE.instantiate()
	item.resource_id = "wood"
	item.quantity = 1
	get_tree().current_scene.add_child(item)
	item.global_position = origin + Vector3(0.0, 0.1, 0.0)
	var side := global_transform.basis.x.normalized()
	item.linear_velocity = side * randf_range(0.4, 0.9) + global_transform.basis.y * 0.35


func _spawn_chips_at(origin: Vector3) -> void:
	var up := global_transform.basis.y.normalized()
	for _i in 3:
		var chip := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3.ONE * 0.07
		chip.mesh = box
		chip.material_override = STYLIZED.create(chip_color)
		get_tree().current_scene.add_child(chip)
		chip.global_position = origin
		var spray := (up * 0.3 + Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))).normalized()
		var tween := chip.create_tween()
		tween.tween_property(chip, "global_position", origin + spray * 0.45, 0.15)
		tween.parallel().tween_property(chip, "scale", Vector3.ZERO, 0.15)
		tween.tween_callback(chip.queue_free)
