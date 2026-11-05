extends RigidBody3D

## Corps unique de chute ET de tronc au sol : même RigidBody du début à la fin.
const ProceduralTree := preload("res://scripts/world/procedural_tree.gd")
const TrunkSegmentBounce := preload("res://scripts/world/trunk_segment_bounce.gd")
const GROUND_ITEM_SCENE := preload("res://scenes/resources/ground_item.tscn")
const STYLIZED := preload("res://scripts/resources/stylized_material.gd")
const GRAVITY := 9.8
const SEGMENT_HITS := 2
const OBSTACLE_LAYER := 8
const GROUND_MASK := 1

var planet: Node3D
var trunk_radius: float = ProceduralTree.TRUNK_RADIUS

var _harvest_enabled := false
var _trunk_xforms: Array[Transform3D] = []
var _alive: Array[bool] = []
var _damage: PackedInt32Array = PackedInt32Array()
var _visual: Node3D
var _chip_color := Color(0.55, 0.34, 0.16)
var _foliage_shed_started := false
var _segment_bounce = TrunkSegmentBounce.new()


func _ready() -> void:
	gravity_scale = 0.0
	freeze = false
	sleeping = false
	can_sleep = false
	collision_layer = OBSTACLE_LAYER
	collision_mask = GROUND_MASK
	if planet == null:
		planet = get_tree().get_first_node_in_group(&"planet") as Node3D


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if planet == null:
		planet = get_tree().get_first_node_in_group(&"planet") as Node3D
	if planet == null:
		return
	var offset: Vector3 = state.transform.origin - planet.global_position
	var distance := offset.length()
	if distance < 0.001:
		return
	var up := offset / distance
	state.apply_central_force(-up * GRAVITY * mass)


## Détache une seule fois le feuillage en RigidBody indépendants (même gravité planétaire).
## Ne touche pas aux collisions / masse / shapes du tronc. Disparition nette après 2 s.
func strip_foliage() -> void:
	if _foliage_shed_started:
		return
	_foliage_shed_started = true
	var visual := get_node_or_null(^"FallVisual") as Node3D
	if visual == null:
		return
	var parent := _world_parent()
	var sources: Array[Node] = []
	for child in visual.get_children():
		if str(child.name).to_lower().begins_with("feuillage"):
			sources.append(child)
	for node in sources:
		var mmi := node as MultiMeshInstance3D
		if mmi == null or mmi.multimesh == null or mmi.multimesh.mesh == null:
			node.free()
			continue
		var multi := mmi.multimesh
		var count := multi.instance_count
		if multi.visible_instance_count >= 0:
			count = mini(count, multi.visible_instance_count)
		for i in count:
			var local_xf := multi.get_instance_transform(i)
			var world_xf := global_transform * local_xf
			var leaf := FoliageLeafBody.new()
			leaf.name = "FoliageLeaf_%d" % i
			leaf.add_to_group(&"foliage_leaf")
			leaf.planet = planet
			leaf.mesh = multi.mesh
			leaf.cast_shadow = mmi.cast_shadow
			parent.add_child(leaf)
			leaf.global_transform = world_xf
			var lever := world_xf.origin - global_position
			leaf.linear_velocity = linear_velocity + angular_velocity.cross(lever)
			leaf.angular_velocity = angular_velocity * 0.35
		mmi.free()


func _world_parent() -> Node:
	var tree := get_tree()
	if tree != null and tree.current_scene != null:
		return tree.current_scene
	if tree != null and tree.root != null:
		return tree.root
	return self


## Active la découpe au sol sur CE même corps (après atterrissage).
func enable_ground_harvest(trunks_local: Array[Transform3D], radius: float) -> void:
	_harvest_enabled = true
	trunk_radius = radius
	_trunk_xforms = trunks_local.duplicate()
	_alive.clear()
	_damage = PackedInt32Array()
	_damage.resize(_trunk_xforms.size())
	for i in _trunk_xforms.size():
		_alive.append(true)
		_damage[i] = 0
	_visual = get_node_or_null(^"FallVisual") as Node3D
	add_to_group(&"harvestable")
	can_sleep = true
	# Garde la physique active (gravité + collisions terrain).
	freeze = false
	sleeping = false


func receive_hit(tool_id: String = "", hit_point: Variant = null) -> bool:
	if not _harvest_enabled:
		return false
	if not tool_id.ends_with("_axe") and tool_id != "axe":
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
	_spawn_chips_at(to_global(ProceduralTree.segment_mid(_trunk_xforms[idx])))
	_bounce_hit_segment(idx)
	if _damage[idx] < SEGMENT_HITS:
		return true
	if _damage[idx] > SEGMENT_HITS:
		return true
	# Laisse le squash du dernier coup se voir avant de retirer le segment.
	var destroy_idx := idx
	get_tree().create_timer(TrunkSegmentBounce.IN_TIME).timeout.connect(
		func() -> void:
			if is_instance_valid(self):
				_destroy_segment(destroy_idx),
		CONNECT_ONE_SHOT
	)
	return true


func aim_point() -> Vector3:
	for i in _trunk_xforms.size():
		if i < _alive.size() and _alive[i]:
			return to_global(ProceduralTree.segment_mid(_trunk_xforms[i]))
	return global_position


func is_exposed() -> bool:
	return true


func _alive_count() -> int:
	var n := 0
	for a in _alive:
		if a:
			n += 1
	return n


func _nearest_alive(local_point: Vector3) -> int:
	var best := -1
	var best_dist := INF
	for i in _trunk_xforms.size():
		if not _alive[i]:
			continue
		var xf := _trunk_xforms[i]
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
	_segment_bounce.clear()
	_alive[idx] = false
	_spawn_wood_at(to_global(ProceduralTree.segment_mid(_trunk_xforms[idx])))
	# Retire uniquement la collision de CE segment (les autres restent).
	var shape := get_node_or_null("SegCollision_%d" % idx)
	if shape != null:
		shape.free()
	_refresh_trunk_visual_only()
	_update_mass_from_alive()
	if _alive_count() <= 0:
		queue_free()


func _bounce_hit_segment(idx: int) -> void:
	if _visual == null:
		_visual = get_node_or_null(^"FallVisual") as Node3D
	_segment_bounce.play(self, _visual, _trunk_xforms, _alive, idx)


func _refresh_trunk_visual_only() -> void:
	if _visual == null:
		_visual = get_node_or_null(^"FallVisual") as Node3D
	if _visual == null:
		return
	var trunks: Array[Transform3D] = []
	for i in _trunk_xforms.size():
		if _alive[i]:
			trunks.append(_trunk_xforms[i])
	# Feuillage en cours de chute visuelle : hors de FallVisual, on ne reconstruit que le tronc.
	var empty: Array[Transform3D] = []
	ProceduralTree.fill_visual(_visual, trunks, empty, empty)


func _update_mass_from_alive() -> void:
	mass = maxf(1.0, float(_alive_count()) * 0.55)


func _spawn_wood_at(origin: Vector3) -> void:
	var item := GROUND_ITEM_SCENE.instantiate()
	item.resource_id = "wood"
	item.quantity = 1
	_world_parent().add_child(item)
	item.global_position = origin + Vector3(0.0, 0.1, 0.0)


func _spawn_chips_at(origin: Vector3) -> void:
	var up := global_transform.basis.y.normalized()
	for _i in 3:
		var chip := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3.ONE * 0.07
		chip.mesh = box
		chip.material_override = STYLIZED.create(_chip_color)
		_world_parent().add_child(chip)
		chip.global_position = origin
		var spray := (up * 0.3 + Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))).normalized()
		var tween := chip.create_tween()
		tween.tween_property(chip, "global_position", origin + spray * 0.45, 0.15)
		tween.parallel().tween_property(chip, "scale", Vector3.ZERO, 0.15)
		tween.tween_callback(chip.queue_free)


## Feuille détachée : gravité planétaire comme le tronc, collision sol seule, free après LIFE.
class FoliageLeafBody extends RigidBody3D:
	const LIFE := 2.0
	const GRAVITY := 9.8
	const GROUND_MASK := 1

	var planet: Node3D
	var mesh: Mesh
	var cast_shadow: GeometryInstance3D.ShadowCastingSetting = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


	func _ready() -> void:
		gravity_scale = 0.0
		freeze = false
		sleeping = false
		can_sleep = true
		mass = 0.12
		linear_damp = 0.05
		angular_damp = 0.08
		# Invisible aux autres corps (ne pousse pas le tronc) ; tombe sur le terrain.
		collision_layer = 0
		collision_mask = GROUND_MASK
		continuous_cd = false
		if planet == null:
			planet = get_tree().get_first_node_in_group(&"planet") as Node3D
		if mesh != null:
			var visual := MeshInstance3D.new()
			visual.mesh = mesh
			visual.cast_shadow = cast_shadow
			add_child(visual)
		var shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 0.22
		shape.shape = sphere
		add_child(shape)
		var timer := get_tree().create_timer(LIFE)
		timer.timeout.connect(queue_free)


	func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
		if planet == null:
			planet = get_tree().get_first_node_in_group(&"planet") as Node3D
		if planet == null:
			return
		var offset: Vector3 = state.transform.origin - planet.global_position
		var distance := offset.length()
		if distance < 0.001:
			return
		var up := offset / distance
		state.apply_central_force(-up * GRAVITY * mass)
