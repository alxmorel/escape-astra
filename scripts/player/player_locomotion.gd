extends RefCounted
class_name PlayerLocomotion

const FARM := preload("res://scripts/farming/farming_config.gd")
const FLOOR_SNAP := 0.04
const SNAP_SPEED := 1.25
const GROUND_BAND := 0.15
const JUMP_GROUND_TOLERANCE := 0.15
const GROUND_PROBE := 0.65
const MAX_WALKABLE_SLOPE := deg_to_rad(72.0)
const SWIM_SPEED := 3.3
const SWIM_ACCEL := 9.0

var airborne := false
var jumping := false
var swimming := false
var swim_moving := false
var underwater := false
var planar_speed := 0.0
var radial_speed := 0.0

var _host: CharacterBody3D
var _water_tint: ColorRect
var _on_obstacle := false
var _locomotion := Vector3.ZERO
var _gravity_tangent := Vector3.ZERO


func setup(host: CharacterBody3D) -> void:
	_host = host
	_host.floor_max_angle = MAX_WALKABLE_SLOPE
	_host.floor_snap_length = FLOOR_SNAP
	_build_water_tint()


func tick(delta: float) -> void:
	var up := surface_up()
	_align_to_surface(up)
	_host.up_direction = up
	_update_water(up)

	if swimming:
		_host.floor_snap_length = 0.0
		_host.floor_stop_on_slope = true
		_swim(delta, up)
		_host.move_and_slide()
		_locomotion = _host.velocity - up * _host.velocity.dot(up)
		_gravity_tangent = Vector3.ZERO
		airborne = false
		jumping = false
		_on_obstacle = false
		if _water_tint != null:
			_water_tint.visible = underwater
		_host.call(&"_update_hunger", delta)
		return

	swim_moving = false
	var gravity_strength := _host.get_gravity().length()
	var gravity_vector := -up * gravity_strength
	var height_above := _height_above_ground()
	var ground_normal := _probe_ground(up)
	var has_contact := ground_normal.length_squared() > 0.5
	var walkable := has_contact and ground_normal.angle_to(up) <= MAX_WALKABLE_SLOPE
	var vertical_speed := _host.velocity.dot(up)
	var can_jump := not jumping and (_on_obstacle or _ground_within_jump_tolerance(up))
	var just_jumped := false
	var controls_locked := bool(_host.get(&"controls_locked"))
	if not controls_locked and Input.is_action_just_pressed(&"jump") and can_jump:
		vertical_speed = float(_host.get(&"jump_velocity"))
		airborne = true
		just_jumped = true
		jumping = true
		_gravity_tangent = Vector3.ZERO
		_host.call(&"_spend_hunger", _jump_hunger())

	var tangent_speed := _locomotion.length()
	var supported := false
	if not just_jumped:
		if _on_obstacle:
			supported = true
		elif tangent_speed < SNAP_SPEED and not airborne and height_above <= FLOOR_SNAP:
			supported = true
		elif (
			tangent_speed < SNAP_SPEED
			and vertical_speed <= SNAP_SPEED
			and height_above <= FLOOR_SNAP
			and not _build_below(up)
		):
			supported = true
		elif (
			tangent_speed < SNAP_SPEED
			and walkable
			and has_contact
			and height_above <= GROUND_BAND
			and vertical_speed <= SNAP_SPEED
		):
			supported = true
		elif has_contact and vertical_speed < 0.0 and height_above <= GROUND_BAND and _host.velocity.dot(ground_normal) < -0.5:
			supported = true
	var support_normal := ground_normal if has_contact else up
	var move_direction := Vector3.ZERO if controls_locked else _get_move_direction(up)
	if supported and move_direction != Vector3.ZERO:
		move_direction = _on_plane(move_direction, support_normal)
		if move_direction.length_squared() < 0.0001:
			move_direction = Vector3.ZERO
		else:
			move_direction = move_direction.normalized()

	var walk_speed := float(_host.get(&"walk_speed"))
	var run_speed := float(_host.get(&"run_speed"))
	var acceleration := float(_host.get(&"acceleration"))
	var deceleration := float(_host.get(&"deceleration"))
	if supported:
		airborne = false
		var carried := _on_plane(_locomotion, support_normal)
		if move_direction == Vector3.ZERO:
			_locomotion = Vector3.ZERO
		else:
			var target_speed := run_speed if _is_running() else walk_speed
			var target_velocity := move_direction * target_speed
			var rate := deceleration if target_velocity.length() < carried.length() - 0.05 else acceleration
			_locomotion = carried.move_toward(target_velocity, rate * delta)
		if move_direction == Vector3.ZERO and (walkable or not has_contact):
			_gravity_tangent = Vector3.ZERO
			_host.velocity = Vector3.ZERO
		elif walkable:
			var gravity_normal := gravity_vector.dot(support_normal)
			var ground_stick := support_normal * (gravity_normal * delta)
			_gravity_tangent = Vector3.ZERO
			_host.velocity = _locomotion + ground_stick
		else:
			var gravity_normal := gravity_vector.dot(support_normal)
			var ground_stick := support_normal * (gravity_normal * delta)
			var gravity_along := gravity_vector - support_normal * gravity_normal
			if _gravity_tangent.length_squared() < 0.0001:
				_gravity_tangent = _on_plane(_host.velocity, support_normal) - carried
			_gravity_tangent = _on_plane(_gravity_tangent, support_normal) + gravity_along * delta
			_host.velocity = _locomotion + _gravity_tangent + ground_stick
		vertical_speed = _host.velocity.dot(up)
	else:
		airborne = true
		var tangent_velocity := _host.velocity - up * _host.velocity.dot(up)
		var target_speed := 0.0
		if move_direction != Vector3.ZERO:
			target_speed = run_speed if _is_running() else walk_speed
		var target_velocity := move_direction * target_speed
		var rate := deceleration if target_velocity.length() < tangent_velocity.length() - 0.05 else acceleration
		tangent_velocity = tangent_velocity.move_toward(target_velocity, rate * delta)
		_locomotion = tangent_velocity
		_gravity_tangent = Vector3.ZERO
		if not just_jumped:
			vertical_speed = _host.velocity.dot(up)
		vertical_speed += gravity_vector.dot(up) * delta
		_host.velocity = tangent_velocity + up * vertical_speed

	_orient_visual(delta, move_direction)

	var resting := _locomotion.length() < SNAP_SPEED and move_direction == Vector3.ZERO
	_host.floor_snap_length = FLOOR_SNAP if supported and resting and not just_jumped else 0.0
	_host.floor_stop_on_slope = supported and (walkable or not has_contact) and move_direction == Vector3.ZERO
	_host.move_and_slide()
	var post_vertical := _host.velocity.dot(up)
	height_above = _height_above_ground()
	ground_normal = _probe_ground(up)
	has_contact = ground_normal.length_squared() > 0.5
	walkable = has_contact and ground_normal.angle_to(up) <= MAX_WALKABLE_SLOPE
	var slide_contact := false if just_jumped else _host.is_on_floor() or _obstacle_support(up) or _standing_on_build(up)
	var passive_grounded := (
		not just_jumped
		and walkable
		and has_contact
		and height_above <= GROUND_BAND
		and absf(post_vertical) <= SNAP_SPEED
		and (resting or post_vertical <= 0.0)
	)
	var contact := slide_contact or passive_grounded
	_on_obstacle = contact
	var grounded := contact or (supported and not just_jumped)
	if grounded:
		airborne = false
		_lock_ground_velocity(
			up,
			ground_normal if has_contact else up,
			move_direction != Vector3.ZERO
		)
		jumping = false
	else:
		airborne = true
	planar_speed = (_locomotion + _gravity_tangent).length()
	radial_speed = _host.velocity.dot(up)
	if _water_tint != null:
		_water_tint.visible = underwater
	_host.call(&"_update_hunger", delta)


func surface_up() -> Vector3:
	var planet: Node3D = _host.get(&"_planet")
	if planet == null:
		return Vector3.UP
	var offset := _host.global_position - planet.global_position
	if offset.length_squared() < 0.001:
		return Vector3.UP
	return offset.normalized()


func walk_radius(world_offset: Vector3) -> float:
	var planet: Node3D = _host.get(&"_planet")
	if planet == null or not planet.has_method(&"get_walk_radius"):
		return 0.0
	return float(planet.call(&"get_walk_radius", world_offset))


func _jump_hunger() -> float:
	return FARM.HUNGER_JUMP


func _orient_visual(delta: float, move_direction: Vector3) -> void:
	var tools = _host.get(&"_tools")
	if tools != null and bool(tools.get(&"punching")):
		return
	var visual: Node3D = _host.get_node(^"Visual")
	var camera_yaw: Node3D = _host.get_node(^"CameraYaw")
	var rotation_speed := float(_host.get(&"rotation_speed"))
	if _is_first_person_view():
		# Snap yaw caméra : arme / bras sans décalage latéral en FPS.
		visual.rotation.y = camera_yaw.rotation.y
	elif move_direction != Vector3.ZERO:
		var local_direction := _host.global_transform.basis.inverse() * move_direction
		var target_yaw := atan2(-local_direction.x, -local_direction.z)
		visual.rotation.y = lerp_angle(visual.rotation.y, target_yaw, rotation_speed * delta)


func _is_first_person_view() -> bool:
	var camera_yaw: Node3D = _host.get_node_or_null(^"CameraYaw")
	return camera_yaw != null and camera_yaw.has_method(&"is_first_person") and bool(camera_yaw.call(&"is_first_person"))


func _build_water_tint() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 0
	var tint := ColorRect.new()
	tint.color = Color(0.05, 0.24, 0.4, 0.34)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	tint.visible = false
	layer.add_child(tint)
	_host.add_child(layer)
	_water_tint = tint


func _update_water(up: Vector3) -> void:
	var was := swimming
	var deep := _in_water(_host.global_position + up * 0.95)
	var hips := _in_water(_host.global_position + up * 0.68)
	swimming = hips if swimming else deep
	underwater = _in_water(_host.global_position + up * 1.38)
	if swimming and not was:
		_host.velocity *= 0.42


func _in_water(point: Vector3) -> bool:
	var planet: Node3D = _host.get(&"_planet")
	return planet != null and planet.has_method(&"point_in_water") and bool(planet.call(&"point_in_water", point))


func _dive_held() -> bool:
	return Input.is_key_pressed(KEY_CTRL)


func _swim(delta: float, up: Vector3) -> void:
	var wish := Vector3.ZERO
	var intent := Vector3.ZERO
	var controls_locked := bool(_host.get(&"controls_locked"))
	if not controls_locked:
		intent = _get_move_direction(up)
		if Input.is_action_pressed(&"jump"):
			intent += up
		if _dive_held():
			intent -= up
		wish = intent
		if not _dive_held() and underwater and wish.dot(up) < 0.25:
			wish += up * 0.45
	swim_moving = intent.length_squared() > 0.0001
	if wish.length_squared() > 1.0:
		wish = wish.normalized()
	elif wish.length_squared() < 0.0001 and underwater and not controls_locked and not _dive_held():
		wish = up
	var target := wish * SWIM_SPEED
	_host.velocity = _host.velocity.move_toward(target, SWIM_ACCEL * delta)
	var flat := wish - up * wish.dot(up)
	planar_speed = (_host.velocity - up * _host.velocity.dot(up)).length()
	radial_speed = _host.velocity.dot(up)
	var tools = _host.get(&"_tools")
	if tools != null and bool(tools.get(&"punching")):
		return
	var visual: Node3D = _host.get_node(^"Visual")
	var camera_yaw: Node3D = _host.get_node(^"CameraYaw")
	var rotation_speed := float(_host.get(&"rotation_speed"))
	if _is_first_person_view():
		visual.rotation.y = camera_yaw.rotation.y
	elif flat.length_squared() > 0.01:
		var local_direction := _host.global_transform.basis.inverse() * flat.normalized()
		visual.rotation.y = lerp_angle(visual.rotation.y, atan2(-local_direction.x, -local_direction.z), rotation_speed * delta)


func _on_plane(vector: Vector3, normal: Vector3) -> Vector3:
	return vector - normal * vector.dot(normal)


func _ground_within_jump_tolerance(up: Vector3) -> bool:
	var space := _host.get_world_3d().direct_space_state
	var from := _host.global_position + up * 0.05
	var to := _host.global_position - up * JUMP_GROUND_TOLERANCE
	var query := PhysicsRayQueryParameters3D.create(from, to, _host.collision_mask, [_host.get_rid()])
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return false
	var normal: Vector3 = hit.normal
	if normal.angle_to(up) > MAX_WALKABLE_SLOPE:
		return false
	var gap := (_host.global_position - (hit.position as Vector3)).dot(up)
	return gap <= JUMP_GROUND_TOLERANCE


func _probe_ground(up: Vector3) -> Vector3:
	if _host.is_on_floor():
		var floor_normal := _host.get_floor_normal()
		if floor_normal.dot(up) > 0.05:
			return floor_normal.normalized()
	if _host.is_on_wall():
		var wall_normal := _host.get_wall_normal()
		if wall_normal.dot(up) > 0.05:
			return wall_normal.normalized()
	var space := _host.get_world_3d().direct_space_state
	var from := _host.global_position + up * 0.45
	var to := _host.global_position - up * GROUND_PROBE
	var query := PhysicsRayQueryParameters3D.create(from, to, _host.collision_mask, [_host.get_rid()])
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return Vector3.ZERO
	var normal: Vector3 = hit.normal
	if normal.dot(up) <= 0.05:
		return Vector3.ZERO
	var gap := (_host.global_position - (hit.position as Vector3)).dot(up)
	if gap > 0.4 or gap < -0.2:
		return Vector3.ZERO
	return normal.normalized()


func _slide_off_barriers(vector: Vector3, up: Vector3) -> Vector3:
	var result := vector
	for i in _host.get_slide_collision_count():
		var normal := _host.get_slide_collision(i).get_normal()
		if normal.angle_to(up) <= MAX_WALKABLE_SLOPE:
			continue
		var into := result.dot(normal)
		if into < 0.0:
			result -= normal * into
	return result


func _lock_ground_velocity(up: Vector3, hinted_normal: Vector3, moving: bool) -> void:
	var normal := hinted_normal
	if _host.is_on_floor():
		var floor_normal := _host.get_floor_normal()
		if floor_normal.dot(up) > 0.05:
			normal = floor_normal.normalized()
	elif _host.is_on_wall():
		var wall_normal := _host.get_wall_normal()
		if wall_normal.dot(up) > 0.05:
			normal = wall_normal.normalized()
	elif normal.length_squared() < 0.5:
		normal = up
	var walkable := normal.angle_to(up) <= MAX_WALKABLE_SLOPE
	if walkable and not moving:
		_locomotion = Vector3.ZERO
		_gravity_tangent = Vector3.ZERO
		_host.velocity = Vector3.ZERO
		return
	var loco := _on_plane(_locomotion, normal)
	if not moving:
		loco = Vector3.ZERO
	_locomotion = loco
	var gravity := Vector3.ZERO
	if not walkable:
		gravity = _slide_off_barriers(_on_plane(_gravity_tangent, normal), up)
	_gravity_tangent = gravity
	var into_ground := minf(_host.velocity.dot(normal), 0.0)
	_host.velocity = loco + gravity + normal * into_ground


func _height_above_ground() -> float:
	var up := surface_up()
	var space := _host.get_world_3d().direct_space_state
	var from := _host.global_position + up * 0.45
	var to := _host.global_position - up * GROUND_PROBE
	var query := PhysicsRayQueryParameters3D.create(from, to, _host.collision_mask, [_host.get_rid()])
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		return (_host.global_position - (hit.position as Vector3)).dot(up)
	var planet: Node3D = _host.get(&"_planet")
	if planet == null:
		return 0.0
	var offset := _host.global_position - planet.global_position
	var distance := offset.length()
	if distance < 0.001:
		return 0.0
	return distance - walk_radius(offset)


func _obstacle_support(up: Vector3) -> bool:
	for i in _host.get_slide_collision_count():
		if _host.get_slide_collision(i).get_normal().dot(up) > 0.3:
			return true
	return false


func _standing_on_build(up: Vector3) -> bool:
	return _build_hit(up, 0.2)


func _build_below(up: Vector3) -> bool:
	var reach := maxf(_height_above_ground(), 0.0) + 1.5
	return _build_hit(up, reach)


func _build_hit(up: Vector3, reach: float) -> bool:
	var space := _host.get_world_3d().direct_space_state
	var from := _host.global_position + up * 0.05
	var ray := PhysicsRayQueryParameters3D.create(from, _host.global_position - up * reach, 8, [_host.get_rid()])
	var hit := space.intersect_ray(ray)
	if hit.is_empty():
		return false
	return (hit.normal as Vector3).dot(up) > 0.3


func _align_to_surface(up: Vector3) -> void:
	var current := _host.global_transform.basis.orthonormalized()
	var aligned := (Basis(Quaternion(current.y, up)) * current).orthonormalized()
	_host.global_transform = Transform3D(aligned, _host.global_position)


func _get_move_direction(up: Vector3) -> Vector3:
	var input := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	if input == Vector2.ZERO:
		return Vector3.ZERO
	var camera_yaw: Node3D = _host.get_node(^"CameraYaw")
	var yaw_basis := camera_yaw.global_transform.basis
	var forward := -yaw_basis.z
	var right := yaw_basis.x
	forward = (forward - up * forward.dot(up)).normalized()
	right = (right - up * right.dot(up)).normalized()
	var direction := right * input.x - forward * input.y
	if direction.length_squared() < 0.001:
		return Vector3.ZERO
	return direction.normalized()


func _is_running() -> bool:
	return Input.is_action_pressed(&"sprint")
