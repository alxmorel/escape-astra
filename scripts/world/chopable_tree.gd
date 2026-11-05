extends "res://scripts/resources/harvestable.gd"

const ProceduralTree := preload("res://scripts/world/procedural_tree.gd")
const FallingTreeBody := preload("res://scripts/world/falling_tree_body.gd")
const TrunkSegmentBounce := preload("res://scripts/world/trunk_segment_bounce.gd")
const OBSTACLE_LAYER := 8
const GROUND_MASK := 1
const SEGMENT_HITS := 2
const HINGE_RELEASE_ANGLE := deg_to_rad(78.0)
const SETTLE_SPEED := 0.45
const SETTLE_ANGULAR := 0.55

var trunk_xforms: Array[Transform3D] = []
var foliage_a: Array[Transform3D] = []
var foliage_b: Array[Transform3D] = []
var trunk_radius: float = ProceduralTree.TRUNK_RADIUS
var trunk_path_count: int = 0

var _segment_damage: PackedInt32Array = PackedInt32Array()
var _segment_alive: Array[bool] = []
var _visual: Node3D
var _collision_body: StaticBody3D
var _falling := false
var _impact_done := false
var _fall_body: RigidBody3D
var _fall_anchor: StaticBody3D
var _fall_joint: HingeJoint3D
var _fall_trunks: Array[Transform3D] = []
var _fall_foliage_a: Array[Transform3D] = []
var _fall_foliage_b: Array[Transform3D] = []
var _fall_dir := Vector3.FORWARD
var _cut_local := Vector3.ZERO
var _cut_normal := Vector3.UP
var _hinge_axis_world := Vector3.RIGHT
var _hinge_released := false
var _settle_frames := 0
var _fall_time := 0.0
var _initial_up_world := Vector3.UP
var _segment_bounce = TrunkSegmentBounce.new()


func setup_procedural(
	visual: Node3D,
	trunks: Variant,
	leaves_a: Variant,
	leaves_b: Variant,
	radius: float,
	path_count: int = 0
) -> void:
	_visual = visual
	trunk_xforms = _to_xform_array(trunks)
	foliage_a = _to_xform_array(leaves_a)
	foliage_b = _to_xform_array(leaves_b)
	trunk_radius = radius
	trunk_path_count = clampi(path_count, 1, maxi(trunk_xforms.size(), 1))
	hits_per_drop = 0
	resource_id = "wood"
	required_tool = "axe"
	_segment_damage = PackedInt32Array()
	_segment_damage.resize(trunk_xforms.size())
	_segment_alive.clear()
	for _i in trunk_xforms.size():
		_segment_damage[_i] = 0
		_segment_alive.append(true)
	call_deferred(&"_rebuild_segment_collision")


func _to_xform_array(raw: Variant) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	if raw is Array:
		for item in raw:
			if item is Transform3D:
				out.append(item)
	return out


func is_chop_falling() -> bool:
	return _falling


func receive_hit(tool_id: String = "", hit_point: Variant = null) -> bool:
	if _falling or _impact_done:
		return false
	if not _accepts_tool(tool_id):
		return false
	if not is_exposed():
		return false
	if trunk_xforms.is_empty():
		return false

	var local_point := _resolve_hit_point(hit_point)
	var idx := _nearest_alive_trunk_index(local_point)
	if idx < 0:
		return false

	_segment_damage[idx] += 1
	var xf := trunk_xforms[idx]
	var axis := xf.basis.y.normalized()
	var along := clampf((local_point - xf.origin).dot(axis), 0.1, ProceduralTree.TRUNK_HEIGHT - 0.1)
	_spawn_chips_at(to_global(xf.origin + axis * along))
	_segment_bounce.play(self, _visual, trunk_xforms, _segment_alive, idx)

	if _segment_damage[idx] < SEGMENT_HITS:
		return true
	if _segment_damage[idx] > SEGMENT_HITS:
		return true

	# Laisse le squash du dernier coup se voir avant coupe / chute.
	var destroy_idx := idx
	var destroy_hit := local_point
	get_tree().create_timer(TrunkSegmentBounce.IN_TIME).timeout.connect(
		func() -> void:
			if is_instance_valid(self) and not _falling:
				_destroy_segment(destroy_idx, destroy_hit),
		CONNECT_ONE_SHOT
	)
	return true


func _resolve_hit_point(hit_point: Variant) -> Vector3:
	if hit_point is Vector3:
		return to_local(hit_point as Vector3)
	if is_inside_tree():
		var players := get_tree().get_nodes_in_group(&"player")
		if not players.is_empty():
			var player := players[0] as Node3D
			if player != null:
				return to_local(player.global_position)
	return Vector3(0.0, aim_height, 0.0)


func _nearest_alive_trunk_index(local_point: Vector3) -> int:
	var best := -1
	var best_dist := INF
	for i in trunk_xforms.size():
		if i >= _segment_alive.size() or not _segment_alive[i]:
			continue
		var xf := trunk_xforms[i]
		var axis := xf.basis.y.normalized()
		var along := clampf((local_point - xf.origin).dot(axis), 0.0, ProceduralTree.TRUNK_HEIGHT)
		var closest := xf.origin + axis * along
		var dist := closest.distance_squared_to(local_point)
		dist += float(i) * 0.00001
		if dist < best_dist:
			best_dist = dist
			best = i
	return best


func _destroy_segment(idx: int, hit_local: Vector3) -> void:
	if idx < 0 or idx >= _segment_alive.size() or not _segment_alive[idx]:
		return
	_segment_bounce.clear()

	var xf := trunk_xforms[idx]
	var axis := xf.basis.y.normalized()
	var along := clampf((hit_local - xf.origin).dot(axis), 0.08, ProceduralTree.TRUNK_HEIGHT - 0.08)
	_cut_local = xf.origin + axis * along
	_cut_normal = axis
	_fall_dir = _cut_side_direction(hit_local, axis)

	var was_support := idx < trunk_path_count
	if was_support:
		# La bûche coupée tombe avec l'arbre (1re bûche au sol), elle n'est pas détruite ici.
		_begin_fall_from_support(idx)
	else:
		_segment_alive[idx] = false
		_refresh_standing_visual()
		_rebuild_segment_collision()


func _cut_side_direction(hit_local: Vector3, axis: Vector3) -> Vector3:
	# Direction de la coupe = côté frappé (déséquilibre naturel).
	var radial := hit_local - (_cut_local)
	radial = radial - axis * radial.dot(axis)
	if radial.length_squared() > 0.0001:
		return radial.normalized()
	var toward := Vector3.FORWARD
	if is_inside_tree():
		var players := get_tree().get_nodes_in_group(&"player")
		if not players.is_empty():
			var player := players[0] as Node3D
			if player != null:
				var to_player := to_local(player.global_position) - _cut_local
				to_player = to_player - axis * to_player.dot(axis)
				if to_player.length_squared() > 0.0001:
					toward = to_player.normalized()
	return toward


func _alive_trunk_xforms() -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for i in trunk_xforms.size():
		if _segment_alive[i]:
			out.append(trunk_xforms[i])
	return out


func _foliage_supported_by_alive() -> Array:
	var alive_trunks := _alive_trunk_xforms()
	var keep_a: Array[Transform3D] = []
	var keep_b: Array[Transform3D] = []
	for xf in foliage_a:
		if _foliage_near_any(xf.origin, alive_trunks):
			keep_a.append(xf)
	for xf in foliage_b:
		if _foliage_near_any(xf.origin, alive_trunks):
			keep_b.append(xf)
	return [keep_a, keep_b]


func _foliage_near_any(pos: Vector3, trunks: Array[Transform3D]) -> bool:
	for xf in trunks:
		var mid := ProceduralTree.segment_mid(xf)
		if pos.distance_squared_to(mid) < 2.8 * 2.8:
			return true
		if pos.distance_squared_to(ProceduralTree.segment_tip(xf)) < 2.4 * 2.4:
			return true
	return false


func _refresh_standing_visual() -> void:
	if _visual == null:
		return
	var leaves: Array = _foliage_supported_by_alive()
	ProceduralTree.fill_visual(_visual, _alive_trunk_xforms(), leaves[0], leaves[1])


func _begin_fall_from_support(cut_idx: int) -> void:
	if _falling:
		return
	_falling = true
	_fall_time = 0.0
	_settle_frames = 0
	_hinge_released = false
	_register_cut()

	var stump_trunks: Array[Transform3D] = []
	var fall_trunks: Array[Transform3D] = []
	var cut_y := _cut_local.y

	for i in trunk_xforms.size():
		if not _segment_alive[i]:
			continue
		var xf := trunk_xforms[i]
		# Segment de coupe : suit la chute (sinon la 1re bûche disparaît / devient intouchable).
		if i == cut_idx:
			fall_trunks.append(xf)
			continue
		var sample := xf.origin + xf.basis.y.normalized() * 0.05
		if i < trunk_path_count and sample.y < cut_y - 0.02:
			stump_trunks.append(xf)
		elif i < trunk_path_count:
			fall_trunks.append(xf)
		elif sample.y >= cut_y - 0.05:
			fall_trunks.append(xf)
		else:
			stump_trunks.append(xf)

	for i in trunk_xforms.size():
		if not _segment_alive[i]:
			continue
		var xf := trunk_xforms[i]
		for fall_xf in fall_trunks:
			if fall_xf.origin.is_equal_approx(xf.origin):
				_segment_alive[i] = false
				break

	var fall_a: Array[Transform3D] = []
	var fall_b: Array[Transform3D] = []
	var stump_a: Array[Transform3D] = []
	var stump_b: Array[Transform3D] = []
	for xf in foliage_a:
		if (xf.origin - _cut_local).dot(_cut_normal) >= -0.02:
			fall_a.append(xf)
		else:
			stump_a.append(xf)
	for xf in foliage_b:
		if (xf.origin - _cut_local).dot(_cut_normal) >= -0.02:
			fall_b.append(xf)
		else:
			stump_b.append(xf)

	if _visual != null:
		ProceduralTree.fill_visual(_visual, stump_trunks, stump_a, stump_b)
	_rebuild_stump_collision(stump_trunks)
	_fall_trunks = fall_trunks
	_fall_foliage_a = fall_a
	_fall_foliage_b = fall_b
	if is_inside_tree() and get_tree().current_scene != null:
		_spawn_falling_body(fall_trunks, fall_a, fall_b)
	remove_from_group(&"harvestable")


func _spawn_falling_body(
	fall_trunks: Array[Transform3D],
	fall_a: Array[Transform3D],
	fall_b: Array[Transform3D]
) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return

	var pivot_world_pos := to_global(_cut_local)
	_initial_up_world = global_transform.basis.y.normalized()
	var toward_world := (global_transform.basis * _fall_dir).normalized()
	toward_world = (toward_world - _initial_up_world * toward_world.dot(_initial_up_world)).normalized()
	if toward_world.length_squared() < 0.0001:
		toward_world = global_transform.basis.x.normalized()
	_hinge_axis_world = _initial_up_world.cross(toward_world).normalized()
	if _hinge_axis_world.length_squared() < 0.0001:
		_hinge_axis_world = global_transform.basis.x.normalized()

	# Ancre fixe au point de coupe (souche).
	_fall_anchor = StaticBody3D.new()
	_fall_anchor.name = "FallAnchor"
	_fall_anchor.collision_layer = 0
	_fall_anchor.collision_mask = 0
	scene.add_child(_fall_anchor)
	_fall_anchor.global_transform = Transform3D(global_transform.basis, pivot_world_pos)

	var falling := FallingTreeBody.new()
	falling.planet = get_tree().get_first_node_in_group(&"planet") as Node3D
	falling.name = "FallingTree"
	falling.collision_layer = OBSTACLE_LAYER
	falling.collision_mask = GROUND_MASK
	falling.continuous_cd = true
	falling.contact_monitor = true
	falling.max_contacts_reported = 6
	falling.linear_damp = 0.02
	falling.angular_damp = 0.04
	falling.can_sleep = false
	falling.freeze = false
	falling.mass = maxf(3.0, float(fall_trunks.size()) * 0.55)
	_fall_body = falling
	scene.add_child(_fall_body)
	_fall_body.global_transform = Transform3D(global_transform.basis, pivot_world_pos)

	var visual := Node3D.new()
	visual.name = "FallVisual"
	_fall_body.add_child(visual)
	var local_trunks: Array[Transform3D] = []
	var local_a: Array[Transform3D] = []
	var local_b: Array[Transform3D] = []
	_to_pivot_space(fall_trunks, local_trunks)
	_to_pivot_space(fall_a, local_a)
	_to_pivot_space(fall_b, local_b)
	ProceduralTree.fill_visual(visual, local_trunks, local_a, local_b)
	_add_fall_collision(local_trunks)

	# COM au-dessus de la coupe + décalage latéral (sinon r×F=0 et pas de bascule).
	var com := _compute_com(local_trunks)
	var fall_local := (_fall_body.global_transform.basis.inverse() * toward_world).normalized()
	if fall_local.length_squared() < 0.0001:
		fall_local = Vector3.RIGHT
	com += fall_local * 0.45
	_fall_body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	_fall_body.center_of_mass = com

	# Charnière au point de coupe. Les limites angulaires DOIVENT être off
	# (sinon le joint fige l'arbre en l'air — FLAG_USE_LIMIT, Godot 4).
	_fall_joint = HingeJoint3D.new()
	_fall_joint.name = "FallHinge"
	scene.add_child(_fall_joint)
	var hinge_basis := Basis()
	hinge_basis.x = _hinge_axis_world
	hinge_basis.y = _initial_up_world
	hinge_basis.z = hinge_basis.x.cross(hinge_basis.y).normalized()
	hinge_basis.y = hinge_basis.z.cross(hinge_basis.x).normalized()
	_fall_joint.global_transform = Transform3D(hinge_basis, pivot_world_pos)
	_fall_joint.node_a = _fall_joint.get_path_to(_fall_anchor)
	_fall_joint.node_b = _fall_joint.get_path_to(_fall_body)
	_fall_joint.set_flag(HingeJoint3D.FLAG_USE_LIMIT, false)

	_fall_body.sleeping = false
	_fall_body.body_entered.connect(_on_fall_body_contact)
	# Feuillage tombe avec la même gravité dès l'abattage (hors collisions du tronc).
	if _fall_body.has_method(&"strip_foliage"):
		_fall_body.call(&"strip_foliage")
	set_physics_process(true)


func _compute_com(local_trunks: Array[Transform3D]) -> Vector3:
	if local_trunks.is_empty():
		return Vector3(0.0, 1.0, 0.0)
	var sum := Vector3.ZERO
	for xf in local_trunks:
		sum += ProceduralTree.segment_mid(xf)
	return sum / float(local_trunks.size())


func _to_pivot_space(source: Array[Transform3D], out: Array[Transform3D]) -> void:
	var pivot := Transform3D(Basis.IDENTITY, _cut_local)
	var inv := pivot.affine_inverse()
	for xf in source:
		out.append(inv * xf)


func _add_fall_collision(local_trunks: Array[Transform3D]) -> void:
	# Un shape par segment, même RigidBody → contact terrain réaliste, structure rigide.
	if local_trunks.is_empty():
		var shape := CollisionShape3D.new()
		shape.name = "SegCollision_0"
		var sphere := SphereShape3D.new()
		sphere.radius = 0.5
		shape.shape = sphere
		shape.position = Vector3(0.0, 0.5, 0.0)
		_fall_body.add_child(shape)
		return
	for i in local_trunks.size():
		var xf := local_trunks[i]
		var collision := CollisionShape3D.new()
		collision.name = "SegCollision_%d" % i
		var cylinder := CylinderShape3D.new()
		cylinder.height = ProceduralTree.TRUNK_HEIGHT * 0.9
		cylinder.radius = maxf(trunk_radius * 0.72, 0.2)
		collision.shape = cylinder
		# Légèrement au-dessus de la coupe pour ne pas chevaucher la souche.
		var mid := xf.origin + xf.basis.y * (ProceduralTree.TRUNK_HEIGHT * 0.5)
		if mid.y < 0.12:
			mid.y = 0.12
		collision.transform = Transform3D(xf.basis, mid)
		_fall_body.add_child(collision)


func _on_fall_body_contact(body: Node) -> void:
	if body == null or body == self or body == _fall_anchor:
		return
	if not _hinge_released:
		_release_hinge()


func _release_hinge() -> void:
	if _hinge_released:
		return
	_hinge_released = true
	if _fall_joint != null and is_instance_valid(_fall_joint):
		_fall_joint.queue_free()
		_fall_joint = null
	if _fall_anchor != null and is_instance_valid(_fall_anchor):
		_fall_anchor.queue_free()
		_fall_anchor = null


func _physics_process(delta: float) -> void:
	if _impact_done or _fall_body == null or not is_instance_valid(_fall_body):
		return
	_fall_time += delta

	var body_up := _fall_body.global_transform.basis.y.normalized()
	var tip_angle := _initial_up_world.angle_to(body_up)
	if not _hinge_released and tip_angle >= HINGE_RELEASE_ANGLE:
		_release_hinge()

	# Si le joint bloque encore (pas de rotation), on le coupe pour laisser la gravité agir.
	if not _hinge_released and _fall_time > 0.6 and tip_angle < deg_to_rad(3.0):
		_release_hinge()

	var planet := get_tree().get_first_node_in_group(&"planet") as Node3D
	var near_ground := false
	if planet != null and planet.has_method(&"get_walk_radius"):
		var tip := _fall_body.to_global(Vector3(0.0, maxf(_fall_body.center_of_mass.y * 1.6, 1.5), 0.0))
		var tip_off: Vector3 = tip - planet.global_position
		var tip_dist := tip_off.length()
		if tip_dist > 0.001:
			var tip_ground: float = planet.call(&"get_walk_radius", tip_off)
			if tip_dist <= tip_ground + 0.55:
				_release_hinge()
				near_ground = true
		var offset: Vector3 = _fall_body.global_position - planet.global_position
		var dist := offset.length()
		if dist > 0.001:
			var ground_radius: float = planet.call(&"get_walk_radius", offset)
			if dist <= ground_radius + 0.9:
				near_ground = true

	var settled := (
		_hinge_released
		and near_ground
		and _fall_body.linear_velocity.length() < SETTLE_SPEED
		and _fall_body.angular_velocity.length() < SETTLE_ANGULAR
	)
	if settled:
		_settle_frames += 1
	else:
		_settle_frames = 0
	# Ne fige jamais un arbre encore debout / en l'air.
	if _settle_frames >= 10 or (_fall_time > 8.0 and near_ground and tip_angle > deg_to_rad(45.0)):
		_impact()


func _impact() -> void:
	if _impact_done:
		return
	_impact_done = true
	set_physics_process(false)
	_release_hinge()

	if _fall_body == null or not is_instance_valid(_fall_body):
		return

	if _fall_body.body_entered.is_connected(_on_fall_body_contact):
		_fall_body.body_entered.disconnect(_on_fall_body_contact)

	# Même RigidBody : découpe active ; feuillage déjà détaché à l'abattage.
	var local_trunks: Array[Transform3D] = []
	_to_pivot_space(_fall_trunks, local_trunks)
	if _fall_body.has_method(&"enable_ground_harvest"):
		_fall_body.call(&"enable_ground_harvest", local_trunks, trunk_radius)

	# Le corps reste dans la scène (gravité + collisions). On lâche juste la ref locale.
	_fall_body = null
	_fall_trunks.clear()
	_fall_foliage_a.clear()
	_fall_foliage_b.clear()


func _spawn_chips_at(origin: Vector3) -> void:
	var up := global_transform.basis.y.normalized()
	for _i in 4:
		var chip := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3.ONE * 0.07
		chip.mesh = box
		chip.material_override = STYLIZED.create(chip_color)
		get_tree().current_scene.add_child(chip)
		chip.global_position = origin
		var spray := (up * 0.35 + Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))).normalized()
		var tween := chip.create_tween()
		tween.tween_property(chip, "global_position", origin + spray * 0.5, 0.16)
		tween.parallel().tween_property(chip, "scale", Vector3.ZERO, 0.16)
		tween.tween_callback(chip.queue_free)


func _rebuild_segment_collision() -> void:
	if _collision_body != null and is_instance_valid(_collision_body):
		_collision_body.queue_free()
		_collision_body = null
	var alive := _alive_trunk_xforms()
	if alive.is_empty():
		return
	_collision_body = StaticBody3D.new()
	_collision_body.name = "TrunkCollision"
	_collision_body.collision_layer = OBSTACLE_LAYER
	_collision_body.collision_mask = 0
	for xf in alive:
		var collision := CollisionShape3D.new()
		var cylinder := CylinderShape3D.new()
		cylinder.height = ProceduralTree.TRUNK_HEIGHT * 0.95
		cylinder.radius = maxf(trunk_radius * 0.75, 0.2)
		collision.shape = cylinder
		collision.transform = Transform3D(xf.basis, xf.origin + xf.basis.y * (ProceduralTree.TRUNK_HEIGHT * 0.5))
		_collision_body.add_child(collision)
	add_child(_collision_body)


func _rebuild_stump_collision(stump_trunks: Array[Transform3D]) -> void:
	if _collision_body != null and is_instance_valid(_collision_body):
		_collision_body.queue_free()
		_collision_body = null
	if stump_trunks.is_empty():
		return
	_collision_body = StaticBody3D.new()
	_collision_body.name = "StumpCollision"
	_collision_body.collision_layer = OBSTACLE_LAYER
	_collision_body.collision_mask = 0
	for xf in stump_trunks:
		var collision := CollisionShape3D.new()
		var cylinder := CylinderShape3D.new()
		cylinder.height = ProceduralTree.TRUNK_HEIGHT * 0.95
		cylinder.radius = maxf(trunk_radius * 0.75, 0.2)
		collision.shape = cylinder
		collision.transform = Transform3D(xf.basis, xf.origin + xf.basis.y * (ProceduralTree.TRUNK_HEIGHT * 0.5))
		_collision_body.add_child(collision)
	add_child(_collision_body)
